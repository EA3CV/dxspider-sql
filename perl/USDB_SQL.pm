package USDB_SQL;

use strict;
use warnings;

use DBI;
use DXVars;
use DXUtil;
use DXDebug;
use IO::File;
use File::Spec;

my $HAVE_GUNZIP = 0;
BEGIN {
	eval {
		require IO::Uncompress::Gunzip;
		IO::Uncompress::Gunzip->import(qw(gunzip $GunzipError));
		1;
	} and $HAVE_GUNZIP = 1;
}

sub new {
	my ($class) = @_;
	my $self = {};
	bless $self, $class;

	$self->{table} = 'usdb';
	$self->{stage} = 'usdb_stage';

	my ($dsn, $user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn     or die "[USDB_SQL] \$sqlite_dsn not defined";
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
	} elsif ($main::db_backend eq 'mysql') {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user     or die "[USDB_SQL] \$mysql_user not defined";
		$pass = $main::mysql_pass;
	} else {
		die "[USDB_SQL] Backend '$main::db_backend' not supported";
	}

	$self->{dbh} = DBI->connect($dsn, $user, $pass, {
		RaiseError => 1,
		AutoCommit => 1,
		sqlite_unicode => 1,
		mysql_enable_utf8mb4 => 1,
		mysql_auto_reconnect => 0,
	}) or die "[USDB_SQL] Error connecting to DB: $DBI::errstr";

	$self->_create_table_if_needed($self->{table});
	$self->_create_table_if_needed($self->{stage}) if $main::db_backend eq 'mysql';

	return $self;
}

sub _create_table_if_needed {
	my ($self, $table) = @_;

	my $sql = ($main::db_backend eq 'mysql')
		? "CREATE TABLE IF NOT EXISTS `$table` (
			`callsign` VARCHAR(16) NOT NULL PRIMARY KEY,
			`city` VARCHAR(128) NOT NULL,
			`state` VARCHAR(32) NOT NULL,
			INDEX `idx_state` (`state`)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
		: "CREATE TABLE IF NOT EXISTS `$table` (
			`callsign` TEXT PRIMARY KEY,
			`city` TEXT NOT NULL,
			`state` TEXT NOT NULL
		)";

	$self->{dbh}->do($sql);
}

sub end {
	my ($self) = @_;
	return unless $self && $self->{dbh};
	$self->{dbh}->disconnect();
	delete $self->{dbh};
}

sub DESTROY {
	my ($self) = @_;
	$self->end();
}

sub get {
	my ($self, $call) = @_;
	return () unless defined $call && length $call;

	$call = uc $call;

	my $sth = $self->{dbh}->prepare("SELECT city, state FROM $self->{table} WHERE callsign = ?");
	$sth->execute($call);
	my ($city, $state) = $sth->fetchrow_array;
	return () unless defined $city && defined $state;
	return ($city, $state);
}

sub add {
	my ($self, $call, $city, $state) = @_;
	return unless defined $call && defined $city && defined $state;

	$call  = uc $call;
	$city  =~ s/[\r\n]+//g;
	$state =~ s/[\r\n]+//g;

	my $sql = ($main::db_backend eq 'mysql')
		? "INSERT INTO $self->{table} (callsign, city, state) VALUES (?, ?, ?)
		   ON DUPLICATE KEY UPDATE city=VALUES(city), state=VALUES(state)"
		: "INSERT OR REPLACE INTO $self->{table} (callsign, city, state) VALUES (?, ?, ?)";

	my $sth = $self->{dbh}->prepare($sql);
	$sth->execute($call, $city, $state);
}

sub del {
	my ($self, $call) = @_;
	return unless defined $call && length $call;
	$call = uc $call;
	my $sth = $self->{dbh}->prepare("DELETE FROM $self->{table} WHERE callsign = ?");
	$sth->execute($call);
}

sub _open_input_fh {
	my ($ofn) = @_;

	return (undef, "Cannot find $ofn") unless -r $ofn;

	if ($ofn =~ /\.gz$/i) {
		if ($HAVE_GUNZIP) {
			my $fh = IO::Uncompress::Gunzip->new($ofn)
				or return (undef, "Cannot gunzip $ofn: $IO::Uncompress::Gunzip::GunzipError");
			return ($fh, undef);
		} else {
			open(my $fh, "-|", "gzip", "-dc", $ofn)
				or return (undef, "Cannot run gzip -dc $ofn: $!");
			return ($fh, undef);
		}
	}

	my $fh = IO::File->new($ofn) or return (undef, "Cannot read $ofn $!");
	return ($fh, undef);
}

# Carga a tabla destino (main o stage) con batch + micro-sleep, usando begin_work correctamente
sub _load_into_table_throttled {
	my ($self, $target_table, @files) = @_;

	my $dbh = $self->{dbh};

	my $BATCH     = ($main::db_backend eq 'mysql') ? 3000 : 2000;
	my $SLEEP_SEC = 0.02;

	# Limpiar tabla
	if ($main::db_backend eq 'mysql') {
		$dbh->do("TRUNCATE TABLE $target_table");
	} else {
		$dbh->do("DELETE FROM $target_table");
	}

	my $sql = ($main::db_backend eq 'mysql')
		? "INSERT INTO $target_table (callsign, city, state) VALUES (?, ?, ?)
		   ON DUPLICATE KEY UPDATE city=VALUES(city), state=VALUES(state)"
		: "INSERT OR REPLACE INTO $target_table (callsign, city, state) VALUES (?, ?, ?)";

	my $sth = $dbh->prepare($sql);

	my $count = 0;
	my $since_commit = 0;

	# Iniciar transacción explícita
	$dbh->begin_work();

	eval {
		for my $ofn (@files) {
			my ($fh, $err) = _open_input_fh($ofn);
			die $err if $err;

			while (defined(my $line = <$fh>)) {
				$line =~ s/[\r\n]+$//;
				next unless $line =~ /\S/;

				my ($call, $city, $state) = split /\|/, $line, 3;
				next unless $call && $city && $state;

				$call = uc $call;

				$sth->execute($call, $city, $state);

				$count++;
				$since_commit++;

				if ($since_commit >= $BATCH) {
					$dbh->commit();
					$dbh->begin_work();
					$since_commit = 0;

					select(undef, undef, undef, $SLEEP_SEC) if $SLEEP_SEC && $SLEEP_SEC > 0;
				}
			}

			eval { $fh->close(); 1 } or eval { close($fh); 1 };
		}

		$dbh->commit();
		1;
	} or do {
		my $e = $@ || "unknown error";
		eval { $dbh->rollback(); };
		die "[USDB_SQL] load into $target_table failed: $e";
	};

	return $count;
}

# MySQL Camino B: stage + diff set-based
sub load {
	my ($self, @files) = @_;
	return "Need a filename" unless @files;

	# SQLite: carga completa directa (suave)
	if ($main::db_backend ne 'mysql') {
		my $n = $self->_load_into_table_throttled($self->{table}, @files);
		return "$n records";
	}

	my $dbh   = $self->{dbh};
	my $main  = $self->{table};
	my $stage = $self->{stage};

	# 1) Cargar a stage (suave)
	my $stage_count = $self->_load_into_table_throttled($stage, @files);

	# 2) Aplicar diffs en bloque
	my $ins = $dbh->do(qq{
		INSERT INTO $main (callsign, city, state)
		SELECT s.callsign, s.city, s.state
		FROM $stage s
		LEFT JOIN $main m ON m.callsign = s.callsign
		WHERE m.callsign IS NULL
	});

	my $upd = $dbh->do(qq{
		UPDATE $main m
		JOIN $stage s ON s.callsign = m.callsign
		SET m.city = s.city, m.state = s.state
		WHERE (m.city <> s.city) OR (m.state <> s.state)
	});

	my $del = $dbh->do(qq{
		DELETE m FROM $main m
		LEFT JOIN $stage s ON s.callsign = m.callsign
		WHERE s.callsign IS NULL
	});

	my ($final) = $dbh->selectrow_array("SELECT COUNT(*) FROM $main");
	$final ||= $stage_count;

	return "$final records (stage:$stage_count ins:$ins upd:$upd del:$del)";
}

1;
