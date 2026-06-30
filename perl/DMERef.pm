package DMERef;

use strict;
use warnings;

use DXUtil;
use DXDebug;

use Storable qw(store retrieve);

my $self = {};
$self->{_db} = undef;

# ---------------------------
# File backend helpers
# ---------------------------
sub _file_path {
    return localdata("dme_ref.store");
}

sub _key {
    my ($dme) = @_;
    $dme //= 0;
    $dme =~ s/\s+//g;
    $dme = 0 + $dme;
    return $dme;
}

sub _load_file_db {
    my $fn = _file_path();
    return (-e $fn) ? retrieve($fn) : {};
}

sub _save_file_db {
    my ($db) = @_;
    my $fn = _file_path();
    store $db, $fn;
    return 1;
}

# ---------------------------
# Main interface
# ---------------------------
sub load {
    if ($main::db_backend && $main::db_backend ne 'file') {
        require DMERef_SQL;
        $self->{_db} = DMERef_SQL->new();
        dbg("DMERef: Loaded SQL backend: $main::db_backend") if isdbg('dme');
        return 1;
    }

    $self->{_db} = undef;
    dbg("DMERef: Loaded file backend") if isdbg('dme');
    return 1;
}

sub upsert {
    my ($dme, $province, $name) = @_;

    return $self->{_db}->upsert($dme, $province, $name) if $self->{_db};

    my $db = _load_file_db();
    my $k  = _key($dme);

    $province //= '';
    $name     //= '';

    $province =~ s/^\s+|\s+$//g;
    $name     =~ s/^\s+|\s+$//g;

    $province = substr($province, 0, 15);
    $name     = substr($name,     0, 40);

    $db->{$k} = {
        dme      => 0 + $k,
        province => $province,
        name     => $name,
    };

    _save_file_db($db);
    return 1;
}

sub read {
    my ($dme) = @_;

    return $self->{_db}->read($dme) if $self->{_db};

    my $db = _load_file_db();
    my $k  = _key($dme);
    return $db->{$k};
}

sub delete {
    my ($dme) = @_;

    return $self->{_db}->delete($dme) if $self->{_db};

    my $db = _load_file_db();
    my $k  = _key($dme);
    delete $db->{$k};
    _save_file_db($db);
    return 1;
}

sub find_by_province {
    my ($province) = @_;
    $province //= '';
    $province =~ s/^\s+|\s+$//g;

    return $self->{_db}->find_by_province($province) if $self->{_db};

    my $db = _load_file_db();
    my @out;

    for my $k (keys %$db) {
        my $r = $db->{$k};
        next if !defined $r->{province};
        next if $r->{province} ne $province;
        push @out, $r;
    }

    return \@out;
}

sub sync_from_csv {
    my ($csvfile, %opts) = @_;

    return $self->{_db}->sync_from_csv($csvfile, %opts) if $self->{_db};

    die "DMERef: sync_from_csv solo soportado en backend SQL\n";
}

1;
