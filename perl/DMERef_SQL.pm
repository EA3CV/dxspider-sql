package DMERef_SQL;

use strict;
use warnings;

use DBI;
use Text::CSV;

# CSV esperado:
#   dme,municipio,provincia
# En tabla:
#   province = provincia (VARCHAR(15))
#   name     = municipio (VARCHAR(40))

sub new {
    my ($class) = @_;
    my $self = {};
    bless $self, $class;

    $self->{table}     = 'dme_ref';
    $self->{table_stg} = 'dme_ref_stg';

    my $dsn;
    my ($user, $pass);

    if ($main::db_backend eq 'sqlite') {
        $dsn  = $main::sqlite_dsn     or die "[DMERef_SQL] \$sqlite_dsn not defined";
        $user = $main::sqlite_dbuser;
        $pass = $main::sqlite_dbpass;
    } elsif ($main::db_backend eq 'mysql') {
        $dsn  = "DBI:mysql:database=$main::mysql_db;host=$main::mysql_host";
        $user = $main::mysql_user     or die "[DMERef_SQL] \$mysql_user not defined";
        $pass = $main::mysql_pass;
    } else {
        die "[DMERef_SQL] Backend '$main::db_backend' not supported";
    }

    $self->{dbh} = DBI->connect($dsn, $user, $pass, {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_unicode       => 1,
        mysql_enable_utf8mb4 => 1,
        mysql_local_infile   => 1,
    }) or die "[DMERef_SQL] Error connecting to DB: $DBI::errstr";

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
                dme      INTEGER NOT NULL PRIMARY KEY,
                province VARCHAR(15) NOT NULL,
                name     VARCHAR(40) NOT NULL
            )
        });

        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                dme      INTEGER NOT NULL PRIMARY KEY,
                province VARCHAR(15) NOT NULL,
                name     VARCHAR(40) NOT NULL
            )
        });

        $dbh->do(qq{ CREATE INDEX IF NOT EXISTS idx_dme_ref_province ON $self->{table}(province) });

    } else {
        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table} (
                dme      INT UNSIGNED NOT NULL,
                province VARCHAR(15)  NOT NULL,
                name     VARCHAR(40)  NOT NULL,
                PRIMARY KEY (dme),
                KEY idx_province (province)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });

        $dbh->do(qq{
            CREATE TABLE IF NOT EXISTS $self->{table_stg} (
                dme      INT UNSIGNED NOT NULL,
                province VARCHAR(15)  NOT NULL,
                name     VARCHAR(40)  NOT NULL,
                PRIMARY KEY (dme),
                KEY idx_province (province)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });
    }

    return 1;
}

# ---------------------------
# CRUD
# ---------------------------
sub read {
    my ($self, $dme) = @_;
    my $sth = $self->{dbh}->prepare(
        qq{SELECT dme, province, name FROM $self->{table} WHERE dme=?}
    );
    $sth->execute(0 + ($dme // 0));
    return $sth->fetchrow_hashref;
}

sub delete {
    my ($self, $dme) = @_;
    my $sth = $self->{dbh}->prepare(
        qq{DELETE FROM $self->{table} WHERE dme=?}
    );
    $sth->execute(0 + ($dme // 0));
    return 1;
}

sub upsert {
    my ($self, $dme, $province, $name) = @_;
    my $dbh = $self->{dbh};
    my $drv = $self->_driver;

    $dme = 0 + ($dme // 0);
    $province //= '';
    $name     //= '';

    $province =~ s/^\s+|\s+$//g;
    $name     =~ s/^\s+|\s+$//g;

    $province = substr($province, 0, 15);
    $name     = substr($name,     0, 40);

    if ($drv eq 'SQLite') {
        my $sth = $dbh->prepare(qq{
            INSERT INTO $self->{table} (dme, province, name)
            VALUES (?, ?, ?)
            ON CONFLICT(dme) DO UPDATE SET
                province=excluded.province,
                name=excluded.name
        });
        $sth->execute($dme, $province, $name);
        return 1;
    }

    my $sth = $dbh->prepare(qq{
        INSERT INTO $self->{table} (dme, province, name)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            province=VALUES(province),
            name=VALUES(name)
    });
    $sth->execute($dme, $province, $name);
    return 1;
}

sub find_by_province {
    my ($self, $province) = @_;
    $province //= '';
    $province =~ s/^\s+|\s+$//g;

    my $sth = $self->{dbh}->prepare(
        qq{SELECT dme, province, name FROM $self->{table} WHERE province=? ORDER BY dme}
    );
    $sth->execute($province);

    my @out;
    while (my $r = $sth->fetchrow_hashref) {
        push @out, $r;
    }
    return \@out;
}

# ---------------------------
# Sync desde CSV: dme,municipio,provincia
# - con cabecera: se ignora en MySQL (IGNORE 1 LINES) y en SQLite (si dme no es numérico)
# - aplica INS/UPD/DEL reales (sin active/last_seen)
# Devuelve hashref: { stage => N, ins => N, upd => N, del => N }
# ---------------------------
sub sync_from_csv {
    my ($self, $csvfile, %opts) = @_;

    my $dbh = $self->{dbh};
    my $drv = $self->_driver;

    $dbh->{AutoCommit} = 0;

    my $stats = { stage => 0, ins => 0, upd => 0, del => 0 };

    eval {
        # 1) staging limpio
        $dbh->do("DELETE FROM $self->{table_stg}");

        # 2) cargar CSV en staging
        if ($drv eq 'SQLite') {
            open my $fh, "<:encoding(UTF-8)", $csvfile
              or die "[DMERef_SQL] No puedo abrir $csvfile: $!\n";

            my $csv = Text::CSV->new({ binary => 1 });

            # staging columns: (dme, province, name)
            # CSV columns:     (dme, municipio, provincia)
            # mapping: province <- provincia ; name <- municipio
            my $ins = $dbh->prepare(qq{
                INSERT INTO $self->{table_stg} (dme, province, name)
                VALUES (?, ?, ?)
                ON CONFLICT(dme) DO UPDATE SET
                    province=excluded.province,
                    name=excluded.name
            });

            while (my $row = $csv->getline($fh)) {
                my ($dme, $municipio, $provincia) = @$row;

                next if !defined $dme;
                $dme =~ s/\s+//g;
                next if $dme !~ /^\d+$/; # ignora cabecera

                $provincia //= '';
                $municipio //= '';

                $provincia =~ s/^\s+|\s+$//g;
                $municipio =~ s/^\s+|\s+$//g;

                $provincia = substr($provincia, 0, 15);
                $municipio = substr($municipio, 0, 40);

                $ins->execute(0 + $dme, $provincia, $municipio);
            }
            close $fh;

        } else {
            # MySQL/MariaDB: staging columns are (dme, province, name)
            # CSV columns are (dme, municipio, provincia)
            # So load as: (dme, name, province)
            my $sth = $dbh->prepare(qq{
                LOAD DATA LOCAL INFILE ?
                INTO TABLE $self->{table_stg}
                CHARACTER SET utf8mb4
                FIELDS TERMINATED BY ',' ENCLOSED BY '"'
                LINES TERMINATED BY '\n'
                IGNORE 1 LINES
                (dme, name, province)
            });
            $sth->execute($csvfile);
        }

        # 2b) stage count
        ($stats->{stage}) = $dbh->selectrow_array(qq{SELECT COUNT(*) FROM $self->{table_stg}});

        # 3) calcular INS/UPD/DEL
        if ($drv eq 'SQLite') {
            ($stats->{ins}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table_stg} s
                LEFT JOIN $self->{table} t ON t.dme = s.dme
                WHERE t.dme IS NULL
            });

            ($stats->{upd}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table_stg} s
                JOIN $self->{table} t ON t.dme = s.dme
                WHERE COALESCE(t.province,'') <> COALESCE(s.province,'')
                   OR COALESCE(t.name,'')     <> COALESCE(s.name,'')
            });

            ($stats->{del}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table} t
                LEFT JOIN $self->{table_stg} s ON s.dme = t.dme
                WHERE s.dme IS NULL
            });

            # 4) aplicar cambios: UPSERT todo staging
            $dbh->do(qq{
                INSERT INTO $self->{table} (dme, province, name)
                SELECT dme, province, name FROM $self->{table_stg}
                ON CONFLICT(dme) DO UPDATE SET
                    province=excluded.province,
                    name=excluded.name
            });

            # 5) aplicar bajas (borrado real)
            $dbh->do(qq{
                DELETE FROM $self->{table}
                WHERE dme NOT IN (SELECT dme FROM $self->{table_stg})
            });

        } else {
            ($stats->{ins}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table_stg} s
                LEFT JOIN $self->{table} t ON t.dme = s.dme
                WHERE t.dme IS NULL
            });

            ($stats->{upd}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table_stg} s
                JOIN $self->{table} t ON t.dme = s.dme
                WHERE IFNULL(t.province,'') <> IFNULL(s.province,'')
                   OR IFNULL(t.name,'')     <> IFNULL(s.name,'')
            });

            ($stats->{del}) = $dbh->selectrow_array(qq{
                SELECT COUNT(*)
                FROM $self->{table} t
                LEFT JOIN $self->{table_stg} s ON s.dme = t.dme
                WHERE s.dme IS NULL
            });

            # 4) aplicar INS/UPD (UPSERT)
            $dbh->do(qq{
                INSERT INTO $self->{table} (dme, province, name)
                SELECT dme, province, name FROM $self->{table_stg}
                ON DUPLICATE KEY UPDATE
                    province=VALUES(province),
                    name=VALUES(name)
            });

            # 5) aplicar DEL (borrado real)
            $dbh->do(qq{
                DELETE t
                FROM $self->{table} t
                LEFT JOIN $self->{table_stg} s ON s.dme = t.dme
                WHERE s.dme IS NULL
            });
        }

        $dbh->commit;
        1;
    } or do {
        my $err = $@ || 'error desconocido';
        eval { $dbh->rollback };
        $dbh->{AutoCommit} = 1;
        die "[DMERef_SQL] sync_from_csv fallo: $err\n";
    };

    $dbh->{AutoCommit} = 1;
    return $stats;
}

1;
