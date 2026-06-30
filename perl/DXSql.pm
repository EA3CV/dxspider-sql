#
# The master SQL module
#
#
#
# Copyright (c) 2006 Dirk Koopman G1TLH
#

package DXSql;

use strict;

use DXDebug;

use vars qw($active);
$active = 0;

sub init
{
	my $dsn = shift;
	return unless $dsn;
	return $active if $active;
	
	eval { 
		require DBI;
	};
	unless ($@) {
		import DBI;
		$active++;
	}
	undef $@;
	return $active;
} 

sub new
{
	my $class = shift;
	my $dsn = shift;
	my $self;
	
	return undef unless $active;
	my $dbh;
	my ($style) = $dsn =~ /^dbi:(\w+):/;
	my $newclass = "DXSql::$style";
	eval "require $newclass";
	if ($@) {
		$active = 0;
		return undef;
	}
	return bless {}, $newclass;
}

sub connect
{
	my $self = shift; 
	my $dsn = shift;
	my $user = shift;
	my $passwd = shift;
	
	my $dbh;
	eval {
		no strict 'refs';
		$dbh = DBI->connect($dsn, $user, $passwd);
		dbg "DXSql $dsn " . $dbh? "connected" : "NOT connected" if isdbg('dxsql');
	};
	unless ($dbh) {
		$active = 0;
		return undef;
	}
	$self->{dbh} = $dbh;
	return $self;
}

sub finish
{
	my $self = shift;
	$self->{dbh}->disconnect;
} 

sub do
{
	my $self = shift;
	my $s = shift;
	
	eval { $self->{dbh}->do($s); }; 
}

sub begin_work
{
	$_[0]->{dbh}->begin_work;
}

sub commit
{
	$_[0]->{dbh}->commit;
}

sub rollback
{
	$_[0]->{dbh}->rollback;
}

sub quote
{
	return $_[0]->{dbh}->quote($_[1]);
}

sub prepare
{
	return $_[0]->{dbh}->prepare($_[1]);
}

sub spot_insert_prepare
{
	my $self = shift;
	return $self->prepare('insert into spot values(?' . ',?' x 15 . ')');
}

sub spot_insert
{
	my $self = shift;
	my $spot = shift;
	my $sth = shift;
	
	if ($sth) {
		push @$spot, undef while  @$spot < 15;
		pop @$spot while @$spot > 15;
		eval {$sth->execute(undef, @$spot)};
	} else {
		my $s = "insert into spot values(NULL,";
		$s .= sprintf("%.1f,", $spot->[0]);
		$s .= $self->quote($spot->[1]) . "," ;
		$s .= $spot->[2] . ',';
		$s .= (length $spot->[3] ? $self->quote($spot->[3]) : 'NULL') . ',';
		$s .= $self->quote($spot->[4]) . ',';
		$s .= $spot->[5] . ',';
		$s .= $spot->[6] . ',';
		$s .= (length $spot->[7] ? $self->quote($spot->[7]) : 'NULL') . ',';
		$s .= $spot->[8] . ',';
		$s .= $spot->[9] . ',';
		$s .= $spot->[10] . ',';
		$s .= $spot->[11] . ',';
		$s .= (length $spot->[12] ? $self->quote($spot->[12]) : 'NULL') . ',';
		$s .= (length $spot->[13] ? $self->quote($spot->[13]) : 'NULL') . ',';
		$s .= (length $spot->[14] ? $self->quote($spot->[14]) : 'NULL') . ')';
		eval {$self->do($s)};
	}
}

sub spot_search
{
	my $self = shift;
	my ($expr, $dayfrom, $dayto, $from, $to, $hint, $dofilter, $dxchan) = @_;

	$dayfrom = 0 if !$dayfrom;
	$dayto   = $Spot::maxdays unless $dayto;
	$dayto   = $dayfrom + $Spot::maxdays if $dayto < $dayfrom;

	$from = 0 unless $from;
	$to   = $Spot::defaultspots unless $to;

	# If we can't see an expression in the expected form, do a pure time-range search.
	$expr ||= '';

	# Map $r->[n] to SQL columns.
	# NOTE: comment is VARBINARY in your schema -> convert to text + CI collation for searches.
	my %col = (
		0  => 'freq',
		1  => 'spotcall',
		2  => 'time',
		3  => 'CONVERT(comment USING utf8mb4) COLLATE utf8mb4_unicode_ci',
		4  => 'spotter',
		5  => 'spotdxcc',
		6  => 'spotterdxcc',
		7  => 'origin',
		8  => 'spotitu',
		9  => 'spotcq',
		10 => 'spotteritu',
		11 => 'spottercq',
		12 => 'spotstate',
		13 => 'spotterstate',
		14 => 'ipaddr',
	);

	dbg("DXSql raw expr: $expr") if isdbg('search');

	# Translate Perl-ish expression into something SQL can execute.
	# We expect things like:
	#   $r->[1] =~ m{...}
	#   $r->[3] =~ m{...}
	#   $r->[1] eq 'XX'
	# etc.
	if ($expr =~ /\$r->\[/) {

		# Basic boolean ops
		$expr =~ s/\|\|/ or /g;
		$expr =~ s/\&\&/ and /g;

		# Comparisons
		$expr =~ s/\beq\b/ = /g;
		$expr =~ s/\bne\b/ <> /g;
		$expr =~ s/==/ = /g;
		$expr =~ s/!=/ <> /g;

		# Replace field references first
		$expr =~ s/\$r->\[(\d+)\]/ exists $col{$1} ? $col{$1} : "NULL" /ge;

		# Convert "=~ m{...}" into "REGEXP '...'"
		# (MariaDB REGEXP will be case-insensitive for VARCHAR under CI collation;
		# for comment we forced a CI collation via CONVERT(... ) COLLATE ...)
		$expr =~ s/\s*=~\s*m\{([^}]*)\}\s*/ REGEXP '$1' /g;

		# Some Filter::Cmd cases generate m{...} without anchors; keep as-is.

		# Safety: strip any remaining Perl artifacts that SQL can't run
		$expr =~ s/\$r\b/NULL/g;

	} else {
		# If it's not a known expression format, don't try to be clever.
		$expr = '';
	}

	# Time range restriction (same logic as original)
	my $fdays  = $dayfrom ? "time <= " . ($main::systime - ($dayfrom * 86400)) : "";
	my $days   = "time >= " . ($main::systime - ($dayto   * 86400));
	my $trange = $fdays ? "($fdays and $days)" : $days;

	$expr = $expr ? "($expr) and $trange" : $trange;

	my $s = qq{
select
  freq, spotcall, time, comment, spotter, spotdxcc, spotterdxcc,
  origin, spotitu, spotcq, spotteritu, spottercq, spotstate, spotterstate, ipaddr
from spot
where $expr
order by time desc
limit $to
};

	dbg("DXSql SQL: $s") if isdbg('search');

	my $ref = $self->{dbh}->selectall_arrayref($s);
	return () unless $ref && ref($ref) eq 'ARRAY';

	return @$ref;
}

1;
