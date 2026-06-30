package DME;

use strict;
use warnings;

use DXUtil;
use DXDebug;

use Storable qw(store retrieve);
use Time::Piece ();

my $self = {};     # instancia única estilo DXSpider
$self->{_db} = undef;

# ---------------------------
# File backend helpers
# ---------------------------
sub _file_path {
    return localdata("dme.store");
}

sub _key {
    my ($award, $ref) = @_;
    $award //= '';
    $ref   //= '';
    return $award . "\t" . $ref;
}

sub _now {
    return Time::Piece::localtime->strftime('%Y-%m-%d %H:%M:%S');
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
        require DME_SQL;
        $self->{_db} = DME_SQL->new();
        dbg("DME: Loaded SQL backend: $main::db_backend") if isdbg('dme');
        return 1;
    }

    $self->{_db} = undef;
    dbg("DME: Loaded file backend") if isdbg('dme');
    return 1;
}

sub upsert {
    my ($award, $ref, $dme, $name) = @_;

    return $self->{_db}->upsert($award, $ref, $dme, $name) if $self->{_db};

    my $db = _load_file_db();
    my $k = _key($award, $ref);

    $db->{$k} = {
        award     => $award,
        ref       => $ref,
        dme       => 0 + ($dme // 0),
        name      => $name // '',
        active    => 1,
        last_seen => _now(),
    };

    _save_file_db($db);
    return 1;
}

sub read {
    my ($award, $ref) = @_;

    return $self->{_db}->read($award, $ref) if $self->{_db};

    my $db = _load_file_db();
    my $k = _key($award, $ref);
    return $db->{$k};
}

sub delete {
    my ($award, $ref) = @_;

    return $self->{_db}->delete($award, $ref) if $self->{_db};

    my $db = _load_file_db();
    my $k = _key($award, $ref);
    delete $db->{$k};
    _save_file_db($db);
    return 1;
}

sub find_by_dme {
    my ($dme, %opts) = @_;
    my $only_active = exists $opts{only_active} ? $opts{only_active} : 1;

    return $self->{_db}->find_by_dme($dme, only_active => $only_active) if $self->{_db};

    my $db = _load_file_db();
    my @out;

    for my $k (keys %$db) {
        my $r = $db->{$k};
        next if $only_active && !$r->{active};
        next if (0 + ($r->{dme} // 0)) != (0 + ($dme // 0));
        push @out, $r;
    }

    return \@out;
}

sub sync_from_csv {
    my ($csvfile, %opts) = @_;

    return $self->{_db}->sync_from_csv($csvfile, %opts) if $self->{_db};

    die "DME: sync_from_csv solo soportado en backend SQL\n";
}

1;

