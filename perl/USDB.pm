#
# Package to handle US Callsign -> City, State translations
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
#

package USDB;

use strict;
use warnings;

use DXVars;
use SysVar;
use DB_File;
use File::Copy;
use DXDebug;
use DXUtil;
use IO::File;

use vars qw(%db $present $dbfn);

# SQL backend handler (loaded on demand)
my $self = {};
$self->{_db} = undef;

localdata_mv("usdb.v1");
$dbfn = localdata("usdb.v1");

sub _using_sql_backend
{
	return ($main::db_backend && $main::db_backend ne 'file') ? 1 : 0;
}

sub init
{
	end();

	if (_using_sql_backend()) {
		require USDB_SQL;
		$self->{_db} = USDB_SQL->new();
		$present = 1;
		dbg("USDB: Loaded from SQL backend: $main::db_backend") if isdbg('usdb');
		return "US Database loaded";
	}

	$self->{_db} = undef;

	if (tie %db, 'DB_File', $dbfn, O_RDWR, 0664, $DB_BTREE) {
		$present = 1;
		return "US Database loaded";
	}
	return "US Database not loaded";
}

sub end
{
	return unless $present;

	if (_using_sql_backend()) {
		$self->{_db}->end() if $self->{_db} && $self->{_db}->can('end');
		$self->{_db} = undef;
		undef $present;
		return;
	}

	untie %db;
	undef $present;
}

sub get
{
	return () unless $present;
	my $call = uc($_[0] // '');
	return () unless $call;

	if (_using_sql_backend()) {
		return $self->{_db}->get($call);
	}

	my $ctyn = $db{$call};
	my @s = split /\|/, $db{$ctyn} if $ctyn;
	return @s;
}

sub _add
{
	my ($db, $call, $city, $state) = @_;

	# lookup the city
	my $s = uc "$city|$state";
	my $ctyn = $db->{$s};
	unless ($ctyn) {
		my $no = $db->{'##'} || 1;
		$ctyn = "#$no";
		$db->{$s} = $ctyn;
		$db->{$ctyn} = $s;
		$no++;
		$db->{'##'} = "$no";
	}
	$db->{uc $call} = $ctyn;
}

sub add
{
	return unless $present;

	if (_using_sql_backend()) {
		return $self->{_db}->add(@_);
	}

	_add(\%db, @_);
}

sub getstate
{
	return () unless $present;
	my @s = get($_[0]);
	return @s ? $s[1] : undef;
}

sub getcity
{
	return () unless $present;
	my @s = get($_[0]);
	return @s ? $s[0] : undef;
}

sub del
{
	return unless $present;

	my $call = uc shift;

	if (_using_sql_backend()) {
		return $self->{_db}->del($call);
	}

	delete $db{$call};
}

#
# load in / update an existing DB with a standard format (GZIPPED)
# "raw" file.
#
# Note that this removes and overwrites the existing DB file / table
# You will need to init again after doing this
#

sub load
{
	return "Need a filename" unless @_;

	if (_using_sql_backend()) {
		require USDB_SQL;
		$self->{_db} ||= USDB_SQL->new();
		return $self->{_db}->load(@_);
	}

	# --- File backend (DB_File) ---
	# create the new output file
	my $a = new DB_File::BTREEINFO;
	$a->{psize} = 4096 * 2;
	my $s = 0;

	# guess a cache size
	for (@_) {
		my $ts = -s;
		$s = $ts if $ts > $s;
	}
	if ($s > 1024 * 1024) {
		$a->{cachesize} = int($s / (1024*1024)) * 3 * 1024 * 1024;
	}

	my %dbn;
	if (-e $dbfn ) {
		copy($dbfn, "$dbfn.old") or return "cannot copy $dbfn -> $dbfn.old $!";
	}

	unlink "$dbfn.new";
	tie %dbn, 'DB_File', "$dbfn.new", O_RDWR|O_CREAT, 0664, $a or return "cannot tie $dbfn.new $!";

	# now write away all the files
	my $count = 0;
	for (@_) {
		my $ofn = shift;

		return "Cannot find $ofn" unless -r $ofn;

		# conditionally handle compressed files
		my $nfn = $ofn;
		if ($nfn =~ /.gz$/i) {
			my $gz;
			eval qq{use Compress::Zlib; \$gz = gzopen(\$ofn, "rb")};
			return "Cannot read compressed files $@ $!" if $@ || !$gz;
			$nfn =~ s/.gz$//i;
			my $of = new IO::File ">$nfn" or return "Cannot write to $nfn $!";
			my ($l, $buf);
			$of->write($buf, $l) while ($l = $gz->gzread($buf));
			$gz->gzclose;
			$of->close;
			$ofn = $nfn;
		}

		my $of = new IO::File "$ofn" or return "Cannot read $ofn $!";

		while (<$of>) {
			my $l = $_;
			$l =~ s/[\r\n]+$//;
			my ($call, $city, $state) = split /\|/, $l;

			_add(\%dbn, $call, $city, $state);

			$count++;
		}
		$of->close;
		unlink $nfn;
	}

	untie %dbn;
	rename "$dbfn.new", $dbfn;
	return "$count records";
}

1;
