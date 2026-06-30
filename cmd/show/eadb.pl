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

# Validación simple (igual que en el form)
return (1, "Usage: sh/eadb <callsign>") if $call !~ /^[A-Z0-9-]{2,16}$/;

# Carga backend (file/mysql/sqlite)
EADB::load();

# Leer por callsign
my $r = EADB::read($call);

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
