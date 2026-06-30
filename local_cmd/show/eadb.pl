#
# show EA station record from EADB (verified preferred)
#
# Usage:
#   sh/eadb <callsign>
#
# Output:
#   Call  DME  Town  Province
#
# Kin EA3CV
#

use strict;
use warnings;

use EADB;

my ($self, $line) = @_;

$line //= '';
$line =~ s/^\s+//;
$line =~ s/\s+$//;

my @args = split /\s+/, $line;

return (1, "Usage: sh/eadb <callsign>") if !@args || @args > 1;

my $call = $args[0] // '';
$call =~ s/^\s+|\s+$//g;
$call = uc($call);

return (1, "Usage: sh/eadb <callsign>") if $call !~ /^[A-Z0-9-]{2,16}$/;

my $r;

# Prefer SQL directly when backend is mysql/sqlite (source of truth: dme_form_submissions)
my $backend = $main::db_backend // 'file';
if ($backend eq 'mysql' || $backend eq 'sqlite') {
    eval {
        require EADB_SQL;
        my $db = EADB_SQL->new();
        $r = $db->read($call);
        1;
    } or do {
        # If SQL fails for any reason, fallback to wrapper
        $r = undef;
    };
}

# Fallback wrapper (file or if SQL failed)
if (!$r) {
    eval {
        EADB::load();
        $r = EADB::read($call);
        1;
    } or do {
        my $err = $@ || 'unknown error';
        $err =~ s/\s+$//;
        return (1, "sh/eadb ERROR: $err");
    };
}

return (1, sprintf("%-16s -> Not Found", $call)) if !$r;

my $dme  = $r->{dme}      // 0;
my $prov = $r->{province} // $r->{provincia} // '';
my $town = $r->{name}     // $r->{municipio} // '';

my $dme5 = sprintf("%05d", int($dme));
my @out;
push @out, sprintf "%-12s %-8s %-30s %-15s", "Call", "DME", "Town", "Province";
push @out, sprintf "%-12s %-8s %-30s %-15s", ("-" x 12), ("-" x 8), ("-" x 30), ("-" x 15);
push @out, sprintf "%-12s %-8s %-30s %-15s", $call, $dme5, $town, $prov;

return (1, @out);
