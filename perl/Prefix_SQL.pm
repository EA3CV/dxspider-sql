package Prefix_SQL;

use strict;
use warnings;
use DBI;
use DXVars;
use DXUtil;
use DXDebug;

sub new {
	my ($class) = @_;
	my $self = {};
	bless $self, $class;

	$self->{table_pre} = 'prefix_pre';
	$self->{table_loc} = 'prefix_loc';

	my $dsn;
	my ($user, $pass);

	if ($main::db_backend eq 'sqlite') {
		$dsn  = $main::sqlite_dsn     or die "[Prefix_SQL] \$sqlite_dsn not defined";
		$user = $main::sqlite_dbuser;
		$pass = $main::sqlite_dbpass;
	} elsif ($main::db_backend eq 'mysql') {
		$dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
		$user = $main::mysql_user     or die "[Prefix_SQL] \$mysql_user not defined";
		$pass = $main::mysql_pass;
	} else {
		die "[Prefix_SQL] Backend '$main::db_backend' not supported";
	}

	$self->{dbh} = DBI->connect($dsn, $user, $pass, {
		RaiseError => 1,
		AutoCommit => 1,
		sqlite_unicode => 1,
		mysql_enable_utf8mb4 => 1,
	}) or die "[Prefix_SQL] Error connecting to DB: $DBI::errstr";

	$self->_create_tables_if_needed();

	return $self;
}

sub _create_tables_if_needed {
	my ($self) = @_;

	if ($main::db_backend eq 'mysql') {
		$self->{dbh}->do(qq{
			CREATE TABLE IF NOT EXISTS `$self->{table_loc}` (
				`id` INT NOT NULL,
				`name` VARCHAR(128) NOT NULL DEFAULT '',
				`dxcc` INT NOT NULL DEFAULT 0,
				`itu` INT NOT NULL DEFAULT 0,
				`cq` INT NOT NULL DEFAULT 0,
				`utcoff` DOUBLE NOT NULL DEFAULT 0,
				`lat` DOUBLE NOT NULL DEFAULT 0,
				`lon` DOUBLE NOT NULL DEFAULT 0,
				`qra` VARCHAR(16) NOT NULL DEFAULT '',
				PRIMARY KEY (`id`)
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
		});

		$self->{dbh}->do(qq{
			CREATE TABLE IF NOT EXISTS `$self->{table_pre}` (
				`pkey` VARCHAR(32) NOT NULL,
				`ref` TEXT NOT NULL,
				PRIMARY KEY (`pkey`)
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
		});
	} else {
		# sqlite
		$self->{dbh}->do(qq{
			CREATE TABLE IF NOT EXISTS $self->{table_loc} (
				id INTEGER PRIMARY KEY,
				name TEXT NOT NULL DEFAULT '',
				dxcc INTEGER NOT NULL DEFAULT 0,
				itu INTEGER NOT NULL DEFAULT 0,
				cq INTEGER NOT NULL DEFAULT 0,
				utcoff REAL NOT NULL DEFAULT 0,
				lat REAL NOT NULL DEFAULT 0,
				lon REAL NOT NULL DEFAULT 0,
				qra TEXT NOT NULL DEFAULT ''
			)
		});

		$self->{dbh}->do(qq{
			CREATE TABLE IF NOT EXISTS $self->{table_pre} (
				pkey TEXT PRIMARY KEY,
				ref TEXT NOT NULL
			)
		});
	}
}

sub store_from {
	my ($self, $pre, $loc) = @_;

	# $pre and $loc are hashrefs. $loc contains blessed Prefix objects but we only use their fields.
	my $dbh = $self->{dbh};

	$dbh->begin_work;

	eval {
		$dbh->do("DELETE FROM $self->{table_pre}");
		$dbh->do("DELETE FROM $self->{table_loc}");

		my $sth_loc = $dbh->prepare("INSERT INTO $self->{table_loc} (id,name,dxcc,itu,cq,utcoff,lat,lon,qra) VALUES (?,?,?,?,?,?,?,?,?)");
		for my $id (sort {$a <=> $b} keys %{$loc}) {
			my $o = $loc->{$id};
			$sth_loc->execute(
				$id,
				$o->{name}   // '',
				$o->{dxcc}   // 0,
				$o->{itu}    // 0,
				$o->{cq}     // 0,
				$o->{utcoff} // 0,
				$o->{lat}    // 0,
				$o->{long}   // $o->{lon} // 0,
				$o->{qra}    // '',
			);
		}
		$sth_loc->finish;

		my $sth_pre = $dbh->prepare("INSERT INTO $self->{table_pre} (pkey,ref) VALUES (?,?)");
		for my $k (keys %{$pre}) {
			my $ref = $pre->{$k};
			next unless defined $k && defined $ref;
			$sth_pre->execute($k, $ref);
		}
		$sth_pre->finish;

		$dbh->commit;
		1;
	} or do {
		my $err = $@ || 'unknown error';
		eval { $dbh->rollback; };
		die "[Prefix_SQL] store_from failed: $err";
	};
}

sub load_into {
	my ($self, $pre, $loc) = @_;

	my $dbh = $self->{dbh};

	%{$pre} = ();
	%{$loc} = ();

	# locations
	my $sth_loc = $dbh->prepare("SELECT id,name,dxcc,itu,cq,utcoff,lat,lon,qra FROM $self->{table_loc}");
	$sth_loc->execute;
	while (my $r = $sth_loc->fetchrow_hashref) {
		my $id = $r->{id};
		$loc->{$id} = bless({
			name   => $r->{name} // '',
			dxcc   => $r->{dxcc} // 0,
			itu    => $r->{itu} // 0,
			cq     => $r->{cq} // 0,
			utcoff => $r->{utcoff} // 0,
			lat    => $r->{lat} // 0,
			long   => $r->{lon} // 0,
			qra    => $r->{qra} // '',
		}, 'Prefix');
	}
	$sth_loc->finish;

	# prefixes
	my $sth_pre = $dbh->prepare("SELECT pkey,ref FROM $self->{table_pre}");
	$sth_pre->execute;
	while (my $r = $sth_pre->fetchrow_hashref) {
		$pre->{$r->{pkey}} = $r->{ref};
	}
	$sth_pre->finish;
}

1;
