package DME_SQL;

use strict;
use warnings;

use DBI;
use Text::CSV;

sub new {
    my ($class) = @_;
    my $self = {};
    bless $self, $class;

    $self->{table}     = 'dme';
    $self->{table_stg} = 'dme_stg';

    my $dsn;
    my ($user, $pass);

    if ($main::db_backend eq 'sqlite') {
        $dsn  = $main::sqlite_dsn     or die "[DME_SQL] \$sqlite_dsn not defined";
        $user = $main::sqlite_dbuser;
        $pass = $main::sqlite_dbpass;
    } elsif ($main::db_backend eq 'mysql') {
        # dxspider data base va en $main::mysql_db (según tu setup)
        $dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
        $user = $main::mysql_user     or die "[DME_SQL] \$mysql_user not defined";
        $pass = $main::mysql_pass;
    } else {
        die "[DME_SQL] Backend '$main::db_backend' not supported";
    }

    $self->{dbh} = DBI->connect($dsn, $user, $pass, {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_unicode      => 1,
        mysql_enable_utf8mb4 => 1,
        mysql_local_infile   => 1,   # para LOAD DATA LOCAL INFILE
    }) or die "[DME_SQL] Error connecting to DB: $DBI::errstr";

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

    if ($drv eq 'SQLite') {
        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table} (
                award     TEXT NOT NULL,
                ref       TEXT NOT NULL,
                dme       INTEGER NOT NULL,
                name      TEXT,
                active    INTEGER NOT NULL DEFAULT 1,
                last_seen TEXT NOT NULL,
                PRIMARY KEY (award, ref)
            )
        });

        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                award TEXT NOT NULL,
                ref   TEXT NOT NULL,
                dme   INTEGER NOT NULL,
                name  TEXT,
                PRIMARY KEY (award, ref)
            )
        });

        $dbh->do(qq{ CREATE INDEX IF NOT EXISTS idx_dme_dme ON $self->{table}(dme) });
        $dbh->do(qq{ CREATE INDEX IF NOT EXISTS idx_dme_award_dme ON $self->{table}(award, dme) });

    } else {
        # MySQL / MariaDB
        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table} (
                award     VARCHAR(5)   NOT NULL,
                ref       VARCHAR(128) NOT NULL,
                dme       INT          NOT NULL,
                name      VARCHAR(255) NULL,
                active    TINYINT(1)   NOT NULL DEFAULT 1,
                last_seen DATETIME     NOT NULL,
                PRIMARY KEY (award, ref),
                KEY idx_dme (dme),
                KEY idx_award_dme (award, dme)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });

        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                award  VARCHAR(5)   NOT NULL,
                ref    VARCHAR(128) NOT NULL,
                dme    INT          NOT NULL,
                name   VARCHAR(255) NULL,
                PRIMARY KEY (award, ref),
                KEY idx_dme (dme)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });
    }

    return 1;
}

# ---------------------------
# CRUD / query
# ---------------------------
sub read {
    my ($self, $award, $ref) = @_;
    my $sth = $self->{dbh}->prepare(
        qq{SELECT award, ref, dme, name, active, last_seen FROM $self->{table} WHERE award=? AND ref=?}
    );
    $sth->execute($award, $ref);
    return $sth->fetchrow_hashref;
}

sub delete {
    my ($self, $award, $ref) = @_;
    my $sth = $self->{dbh}->prepare(
        qq{DELETE FROM $self->{table} WHERE award=? AND ref=?}
    );
    $sth->execute($award, $ref);
    return 1;
}

sub upsert {
    my ($self, $award, $ref, $dme, $name) = @_;
    my $dbh = $self->{dbh};
    my $drv = $self->_driver;

    if ($drv eq 'SQLite') {
        my $sth = $dbh->prepare(qq{
            INSERT INTO $self->{table} (award, ref, dme, name, active, last_seen)
            VALUES (?, ?, ?, ?, 1, datetime('now'))
            ON CONFLICT(award, ref) DO UPDATE SET
                dme=excluded.dme,
                name=excluded.name,
                active=1,
                last_seen=datetime('now')
        });
        $sth->execute($award, $ref, $dme, $name);
        return 1;
    }

    my $sth = $dbh->prepare(qq{
        INSERT INTO $self->{table} (award, ref, dme, name, active, last_seen)
        VALUES (?, ?, ?, ?, 1, NOW())
        ON DUPLICATE KEY UPDATE
            dme=VALUES(dme),
            name=VALUES(name),
            active=1,
            last_seen=NOW()
    });
    $sth->execute($award, $ref, $dme, $name);
    return 1;
}

sub find_by_dme {
    my ($self, $dme, %opts) = @_;
    my $only_active = exists $opts{only_active} ? $opts{only_active} : 1;

    my $sql = qq{
        SELECT award, ref, dme, name, active, last_seen
        FROM $self->{table}
        WHERE dme = ?
    };
    $sql .= " AND active=1" if $only_active;

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($dme);

    my @out;
    while (my $r = $sth->fetchrow_hashref) {
        push @out, $r;
    }
    return \@out;
}

# ---------------------------
# Sync desde CSV: award,ref,dme,"name" (sin cabecera)
# ---------------------------
sub sync_from_csv {
    my ($self, $csvfile, %opts) = @_;
    my $days_inactive = exists $opts{days_inactive} ? $opts{days_inactive} : 2;

    my $dbh = $self->{dbh};
    my $drv = $self->_driver;

    # Transacción manual
    $dbh->{AutoCommit} = 0;

    eval {
        # 1) staging limpio
        $dbh->do("DELETE FROM $self->{table_stg}");

        # 2) cargar CSV en staging
        if ($drv eq 'SQLite') {
            open my $fh, "<:encoding(UTF-8)", $csvfile
              or die "[DME_SQL] No puedo abrir $csvfile: $!\n";

            my $csv = Text::CSV->new({ binary => 1 });

            my $ins = $dbh->prepare(qq{
                INSERT INTO $self->{table_stg} (award, ref, dme, name)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(award, ref) DO UPDATE SET
                    dme=excluded.dme,
                    name=excluded.name
            });

            while (my $row = $csv->getline($fh)) {
                my ($award, $ref, $dme, $name) = @$row;
                next if !defined $award || !defined $ref || !defined $dme || !defined $name;
                next if $award eq '' || $ref eq '' || $dme eq '' || $name eq '';
                next if $dme !~ /^\d+$/;
                $ins->execute($award, $ref, int($dme), $name);
            }
            close $fh;

        } else {
            my $sth = $dbh->prepare(qq{
                LOAD DATA LOCAL INFILE ?
                INTO TABLE $self->{table_stg}
                CHARACTER SET utf8mb4
                FIELDS TERMINATED BY ',' ENCLOSED BY '"'
                LINES TERMINATED BY '\n'
                (award, ref, dme, name)
            });
            $sth->execute($csvfile);
        }

        # 3) upsert main desde staging (altas + mods) y last_seen/active
        if ($drv eq 'SQLite') {
            $dbh->do(qq{
                INSERT INTO $self->{table} (award, ref, dme, name, last_seen, active)
                SELECT award, ref, dme, name, datetime('now'), 1
                FROM $self->{table_stg}
                ON CONFLICT(award, ref) DO UPDATE SET
                    dme=excluded.dme,
                    name=excluded.name,
                    last_seen=excluded.last_seen,
                    active=1
            });

            # 4) bajas robustas (fusible)
            my $days = int($days_inactive);
            $dbh->do(qq{
                UPDATE $self->{table}
                SET active=0
                WHERE last_seen < datetime('now', '-' || ? || ' days')
            }, undef, $days);

        } else {
            $dbh->do(qq{
                INSERT INTO $self->{table} (award, ref, dme, name, last_seen, active)
                SELECT award, ref, dme, name, NOW(), 1
                FROM $self->{table_stg}
                ON DUPLICATE KEY UPDATE
                    dme=VALUES(dme),
                    name=VALUES(name),
                    last_seen=VALUES(last_seen),
                    active=1
            });

            my $days = int($days_inactive);
            $dbh->do(qq{
                UPDATE $self->{table}
                SET active=0
                WHERE last_seen < NOW() - INTERVAL ? DAY
            }, undef, $days);
        }

        $dbh->commit;
        1;
    } or do {
        my $err = $@ || 'error desconocido';
        eval { $dbh->rollback };
        $dbh->{AutoCommit} = 1;
        die "[DME_SQL] sync_from_csv fallo: $err\n";
    };

    $dbh->{AutoCommit} = 1;
    return 1;
}

1;

