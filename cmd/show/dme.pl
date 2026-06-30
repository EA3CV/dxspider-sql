#
# show the DME award references for a given DME number
#
# Usage:
#   show/dme <dme>
#   show/dme <dme> <award>
#   show/dme <dme> <ref>
#   show/dme <dme> <award,ref>
#
# Output columns: DME  Reference  Name
# Sorted by Reference
#
# Kin EA3CV <ea3cv@cronux.net>
#
# 20260210 v1.0
#

use strict;
use warnings;

use DME;

my ($self, $line) = @_;

$line //= '';
$line =~ s/^\s+//;
$line =~ s/\s+$//;

my @out;

# Carga backend (file/mysql/sqlite)
DME::load();

my @args = split /\s+/, $line;

if (!@args || @args > 2) {
    return (1, "Usage: show/dme <dme> [award|ref|award,ref]");
}

my $dme_in = $args[0];
if (!$dme_in || $dme_in !~ /^\d{1,5}$/) {
    return (1, "Usage: show/dme <dme> [award|ref|award,ref]");
}

my $dme = int($dme_in);

my $filter = $args[1] // '';
$filter = uc($filter);

my $filter_award = '';
my $filter_ref   = '';

# Si viene "AWARD,REF"
if ($filter =~ /^([A-Z0-9]{2,5}),(.+)$/) {
    $filter_award = $1;
    $filter_ref   = $2;
}
# Si viene solo award (DVGE, DCE, etc)
elsif ($filter =~ /^[A-Z0-9]{2,5}$/) {
    $filter_award = $filter;
}
# Si viene una referencia completa (VGCR-054, etc)
elsif ($filter ne '') {
    $filter_ref = $filter;
}

# Recupera registros por DME
my $rows = DME::find_by_dme($dme, only_active => 1) || [];

# Aplica filtros si procede
if ($filter_award ne '') {
    @$rows = grep { ($_->{award} // '') eq $filter_award } @$rows;
}

if ($filter_ref ne '') {
    @$rows = grep { uc($_->{ref} // '') eq $filter_ref } @$rows;
}

if (!@$rows) {
    if ($filter_award || $filter_ref) {
        return (1, sprintf("DME %05d -> Not Found (filter=%s)", $dme, $args[1]));
    }
    return (1, sprintf("DME %05d -> Not Found", $dme));
}

# Orden por reference, y si empata por award
my @sorted = sort {
    ($a->{ref} // '') cmp ($b->{ref} // '')
    ||
    ($a->{award} // '') cmp ($b->{award} // '')
} @$rows;

# Cabecera
push @out, sprintf "%-5s  %-5s  %-12s  %s", "DME", "AWD", "Reference", "Name";
push @out, sprintf "%-5s  %-5s  %-12s  %s", ("-" x 5), ("-" x 5), ("-" x 12), ("-" x 30);

for my $r (@sorted) {
    my $award = $r->{award} // '';
    my $ref   = $r->{ref}   // '';
    my $name  = $r->{name}  // '';

    push @out, sprintf "%05d  %-5s  %-12s  %s", $dme, $award, $ref, $name;
}

return (1, @out);
