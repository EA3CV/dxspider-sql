#
# show DME province + name from dme_ref
#
# Usage:
#   sh/dmedb <dme>
#
# Output:
#   DME  Province  Town
#
# Kin EA3CV
#

use strict;
use warnings;

use DMERef;

my ($self, $line) = @_;

$line //= '';
$line =~ s/^\s+//;
$line =~ s/\s+$//;

my @args = split /\s+/, $line;

return (1, "Usage: sh/dmedb <dme>") if !@args || @args > 1;

my $dme_in = $args[0] // '';
return (1, "Usage: sh/dmedb <dme>") if $dme_in !~ /^\d{1,5}$/;

my $dme = int($dme_in);

# Carga backend (file/mysql/sqlite)
DMERef::load();

my $r = DMERef::read($dme);

return (1, sprintf("DME %05d -> Not Found", $dme)) if !$r;

my $prov = $r->{province} // '';
my $name = $r->{name}     // '';

my @out;
push @out, sprintf "%-5s  %-15s  %s", "DME", "Province", "Town";
push @out, sprintf "%-5s  %-15s  %s", ("-" x 5), ("-" x 15), ("-" x 30);
push @out, sprintf "%05d  %-15s  %s", $dme, $prov, $name;

return (1, @out);
