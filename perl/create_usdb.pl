#!/usr/bin/env perl
#
# create a USDB file from a standard raw file (which is GZIPPED BTW)
#
# Hash-gate: si el contenido no cambia, NO tocamos la DB (evita CPU/lock)
#

use strict;

BEGIN {
	use vars qw($root);

	$root = "/spider";
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/perl";
	unshift @INC, "$root/local";
}

use DXVars;
use SysVar;
use USDB;

# Para hash seguro del contenido descomprimido
use Digest::SHA qw(sha256_hex);

# Intentar gunzip en streaming
my $HAVE_GUNZIP = 0;
BEGIN {
	eval {
		require IO::Uncompress::Gunzip;
		IO::Uncompress::Gunzip->import(qw(gunzip $GunzipError));
		1;
	} and $HAVE_GUNZIP = 1;
}

die "no input (usdbraw?) files specified\n" unless @ARGV;

# Dónde guardamos el hash del último fichero procesado
# (persistente en el contenedor/host si /spider/local_data está montado)
my $hashfile = "$root/local_data/usdbraw.sha256";

sub open_stream {
	my ($fn) = @_;
	if ($fn =~ /\.gz$/i) {
		if ($HAVE_GUNZIP) {
			my $fh = IO::Uncompress::Gunzip->new($fn)
				or die "Cannot gunzip $fn: $IO::Uncompress::Gunzip::GunzipError\n";
			return $fh;
		} else {
			open(my $fh, "-|", "gzip", "-dc", $fn) or die "Cannot run gzip -dc $fn: $!\n";
			return $fh;
		}
	} else {
		open(my $fh, "<", $fn) or die "Cannot read $fn: $!\n";
		return $fh;
	}
}

sub sha256_of_uncompressed {
	my ($fn) = @_;
	my $fh = open_stream($fn);

	my $sha = Digest::SHA->new(256);
	my $buf;

	# Leer en bloques (rápido y sin cargar en RAM)
	while (1) {
		my $read = read($fh, $buf, 1024 * 1024);   # 1 MiB
		last unless $read;
		$sha->add(substr($buf, 0, $read));
	}

	eval { $fh->close(); 1 } or eval { close($fh); 1 };
	return $sha->hexdigest;
}

sub read_prev_hash {
	return undef unless -r $hashfile;
	open(my $fh, "<", $hashfile) or return undef;
	my $h = <$fh>;
	close($fh);
	return undef unless defined $h;
	$h =~ s/[\r\n]+$//;
	return $h || undef;
}

sub write_hash {
	my ($h) = @_;
	# asegúrate de que exista el dir
	my $dir = "$root/local_data";
	eval { mkdir $dir unless -d $dir; 1; };
	open(my $fh, ">", $hashfile) or die "Cannot write $hashfile: $!\n";
	print $fh $h, "\n";
	close($fh);
}

# 1) Calcula hash del contenido (descomprimido)
my $new_hash = sha256_of_uncompressed($ARGV[0]);
my $old_hash = read_prev_hash();

# 2) Si no cambia, no hacemos nada
if (defined $old_hash && $old_hash eq $new_hash) {
	print "\nUSDB: no changes (sha256 match), skipping load\n";
	exit(0);
}

# 3) Si cambia, guardamos hash y cargamos
write_hash($new_hash);

print "\n", USDB::load(@ARGV), "\n";
exit(0);
