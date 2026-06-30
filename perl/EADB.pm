#
# EADB.pm — EA Database (file backend)
#
# DB_File hash:
#   key   = CALLSIGN (upper)
#   value = "dme|province|municipio|verified|created_at|updated_at|verified_at|verified_by"
#
# Notes:
# - The DB is created automatically if missing (DB_File O_CREAT).
#

package EADB;

use strict;
use warnings;

our $obj;

sub load {
    return 1 if $obj;

    if ($main::db_backend eq 'mysql' || $main::db_backend eq 'sqlite') {
        require EADB_SQL;
        $obj = EADB_SQL->new();
        return 1;
    }

    # Si más adelante quieres backend file, lo añadimos aquí.
    die "[EADB] Backend '$main::db_backend' not supported (only mysql/sqlite implemented)\n";
}

sub _need {
    die "[EADB] Not loaded (call EADB::load first)\n" unless $obj;
}

sub read {
    my ($call) = @_;
    _need();
    return $obj->read($call);
}

sub upsert {
    my ($call, $dme, $province, $name, $verified, $verified_by) = @_;
    _need();
    return $obj->upsert($call, $dme, $province, $name, $verified, $verified_by);
}

sub delete {
    my ($call) = @_;
    _need();
    return $obj->delete($call);
}

sub exists {
    my ($call) = @_;
    _need();
    return $obj->exists($call);
}

sub find_by_province {
    my ($province, %opts) = @_;
    _need();
    return $obj->find_by_province($province, %opts);
}

sub list_calls {
    _need();
    return $obj->list_calls();
}

1;
