#!/usr/bin/env perl

use strict;
use warnings;

# Si está en entorno DXSpider, tendremos $main::db_backend, y localdata()
BEGIN { eval { require DXUtil; DXUtil->import(); 1 } or do { }; }

my $CSV = "/spider/local_data/dme_ref.csv";
if (defined &localdata) {
  my $maybe = localdata("dme_ref.csv");
  $CSV = $maybe if defined $maybe && $maybe =~ m{^/spider/local_data/}i;
}

die "DME_REF: no existe $CSV\n" unless -e $CSV;

my $backend = $main::db_backend // 'file';

# Este script es para actualizar TABLA (SQL). Si estás en file, lo dejamos claro.
if ($backend eq 'file' || $backend eq '') {
  die "DME_REF: backend=file. Este script está pensado para actualizar la tabla SQL dme_ref usando dme_ref.csv\n";
}

die "DME_REF: backend '$backend' no soportado (esperado: mysql|sqlite)\n"
  if $backend ne 'mysql' && $backend ne 'sqlite';

require DMERef_SQL;

my $db = DMERef_SQL->new();

my $st = $db->sync_from_csv($CSV);

printf STDERR "DME_REF: %s aplicado desde %s -> stage=%d ins=%d upd=%d del=%d\n",
  $backend, $CSV, $st->{stage}, $st->{ins}, $st->{upd}, $st->{del};

exit 0;
