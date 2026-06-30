#
# EADB_SQL.pm — EA Database (SQL backend)
#
# Backend real: dme_form_submissions
# - Source of truth: rows with verified=1
# - read() returns the verified row (latest by verified_at/created_at)
#
# Keeps the same "shape" as other modules:
# - new() selects sqlite/mysql and connects
# - _create_tables_if_needed() only creates OPTIONAL staging table
#
# Fields in dme_form_submissions:
#   callsign, dme, provincia, municipio, verified, created_at, updated_at, verified_at, verified_by
#

package EADB_SQL;

use strict;
use warnings;

use DBI;

sub new {
    my ($class) = @_;
    my $self = {};
    bless $self, $class;

    # IMPORTANT: main table is dme_form_submissions (already exists)
    $self->{table}     = 'dme_form_submissions';

    # Optional staging (only if you ever need it)
    $self->{table_stg} = 'eadb_stg';

    my $dsn;
    my ($user, $pass);

    if ($main::db_backend eq 'sqlite') {
        $dsn  = $main::sqlite_dsn     or die "[EADB_SQL] \$sqlite_dsn not defined";
        $user = $main::sqlite_dbuser;
        $pass = $main::sqlite_dbpass;
    } elsif ($main::db_backend eq 'mysql') {
        $dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
        $user = $main::mysql_user     or die "[EADB_SQL] \$mysql_user not defined";
        $pass = $main::mysql_pass;
    } else {
        die "[EADB_SQL] Backend '$main::db_backend' not supported";
    }

    $self->{dbh} = DBI->connect($dsn, $user, $pass, {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_unicode       => 1,
        mysql_enable_utf8mb4 => 1,
        mysql_local_infile   => 1,
    }) or die "[EADB_SQL] Error connecting to DB: $DBI::errstr";

    $self->_create_tables_if_needed();

    return $self;
}

sub _driver {
    my ($self) = @_;
    return $self->{dbh}->{Driver}->{Name} // '';
}

sub _create_tables_if_needed {
    my ($self) = @_;
    my $dbh = $self->{dbh};
    my $drv = $self->_driver;

    # NOTE:
    # - We DO NOT create dme_form_submissions here (it already exists and has more fields).
    # - We only create an optional staging table if you ever want sync/import workflows here.

    if ($drv eq 'SQLite') {
        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                callsign   VARCHAR(16) NOT NULL PRIMARY KEY,
                dme        INTEGER NOT NULL,
                provincia  VARCHAR(15) NOT NULL,
                municipio  VARCHAR(40) NOT NULL,
                verified   INTEGER NOT NULL DEFAULT 0
            )
        });
        $dbh->do(qq{ CREATE INDEX IF NOT EXISTS idx_eadb_stg_verified ON $self->{table_stg}(verified) });
        $dbh->do(qq{ CREATE INDEX IF NOT EXISTS idx_eadb_stg_prov ON $self->{table_stg}(provincia) });

    } else {
        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                callsign   VARCHAR(16) NOT NULL,
                dme        INT UNSIGNED NOT NULL,
                provincia  VARCHAR(15)  NOT NULL,
                municipio  VARCHAR(40)  NOT NULL,
                verified   TINYINT(1)   NOT NULL DEFAULT 0,
                PRIMARY KEY (callsign),
                KEY idx_verified (verified),
                KEY idx_prov (provincia),
                KEY idx_dme (dme)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });
    }

    return 1;
}

sub _norm_call {
    my ($c) = @_;
    $c //= '';
    $c =~ s/^\s+|\s+$//g;
    return uc($c);
}

# ---------------------------
# CRUD (read-mostly over verified rows)
# ---------------------------

sub read {
    my ($self, $call) = @_;
    $call = _norm_call($call);
    return undef unless $call;

    # Return the "best" row:
    # - prefer verified=1 (we filter to verified=1)
    # - if there are multiple verified rows (shouldn't happen), take latest
    my $sth = $self->{dbh}->prepare(qq{
        SELECT
            callsign,
            dme,
            provincia AS province,
            municipio AS name,
            verified,
            created_at,
            updated_at,
            verified_at,
            verified_by
        FROM $self->{table}
        WHERE callsign = ? AND verified = 1
        ORDER BY verified_at DESC, created_at DESC
        LIMIT 1
    });
    $sth->execute($call);
    return $sth->fetchrow_hashref;
}

sub exists {
    my ($self, $call) = @_;
    $call = _norm_call($call);
    return 0 unless $call;

    my $sth = $self->{dbh}->prepare(qq{
        SELECT 1
        FROM $self->{table}
        WHERE callsign = ? AND verified = 1
        LIMIT 1
    });
    $sth->execute($call);
    my ($one) = $sth->fetchrow_array;
    return $one ? 1 : 0;
}

# WARNING: Writing into dme_form_submissions changes workflow.
# This implementation inserts a NEW row (verified can be 0/1).
# If you don't want EADB to write here, tell me and I will make upsert() die.
sub upsert {
    my ($self, $call, $dme, $province, $name, $verified, $verified_by) = @_;
    my $dbh = $self->{dbh};

    $call = _norm_call($call);
    return 0 unless $call;

    $dme = 0 + ($dme // 0);
    $province //= '';
    $name     //= '';
    $verified = 0 + ($verified // 0);
    $verified_by //= undef;

    $province =~ s/^\s+|\s+$//g;
    $name     =~ s/^\s+|\s+$//g;

    $province = substr($province, 0, 15);
    $name     = substr($name,     0, 40);

    # Minimal insert; keeps email private/placeholder
    my $email = 'import@cronux.net';
    my $comment = 'EADB upsert';

    my $sth = $dbh->prepare(qq{
        INSERT INTO $self->{table}
            (created_at, callsign, email, provincia, municipio, dme, comentarios, ip, user_agent, updated_at,
             verified, verified_at, verified_by)
        VALUES
            (NOW(), ?, ?, ?, ?, ?, ?, NULL, NULL, NOW(),
             ?, IF(?=1, NOW(), NULL), ?)
    });

    $sth->execute($call, $email, $province, $name, $dme, $comment, $verified, $verified, $verified_by);
    return 1;
}

# "delete" here means: remove verified row(s) for that callsign (safe default)
sub delete {
    my ($self, $call) = @_;
    $call = _norm_call($call);
    return 0 unless $call;

    my $sth = $self->{dbh}->prepare(qq{
        DELETE FROM $self->{table}
        WHERE callsign = ? AND verified = 1
    });
    $sth->execute($call);
    return 1;
}

sub find_by_province {
    my ($self, $province, %opts) = @_;
    $province //= '';
    $province =~ s/^\s+|\s+$//g;

    # default: only verified (EADB = valid DB)
    my $only_verified = exists $opts{only_verified} ? ($opts{only_verified} ? 1 : 0) : 1;

    my $sql = qq{
        SELECT
            callsign,
            dme,
            provincia AS province,
            municipio AS name,
            verified
        FROM $self->{table}
        WHERE provincia = ?
    };
    $sql .= " AND verified=1" if $only_verified;
    $sql .= " ORDER BY callsign";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($province);

    my @out;
    while (my $r = $sth->fetchrow_hashref) {
        push @out, $r;
    }
    return \@out;
}

sub list_calls {
    my ($self) = @_;

    # list only verified calls (EADB semantics)
    my $sth = $self->{dbh}->prepare(qq{
        SELECT callsign
        FROM $self->{table}
        WHERE verified = 1
        ORDER BY callsign
    });
    $sth->execute();

    my @out;
    while (my ($c) = $sth->fetchrow_array) {
        push @out, $c if defined $c;
    }
    return \@out;
}

1;
