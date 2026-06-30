#
# show (or find) list of bad dx nodes
#
# Copyright (c) 2021-2023 - Dirk Koopman G1TLH
#
# Modify by EA3CV
#

sub _expand_ipv6 {
	my ($ip) = @_;
	return unless defined $ip;

	# soporta IPv4 embebida al final, p.e. ::ffff:192.0.2.1
	if ($ip =~ /(.*:)(\d+\.\d+\.\d+\.\d+)$/) {
		my ($head, $v4) = ($1, $2);
		my @o = split /\./, $v4;
		return unless @o == 4 && !grep { $_ !~ /^\d+$/ || $_ < 0 || $_ > 255 } @o;
		$ip = sprintf("%s%x:%x", $head, ($o[0] << 8) + $o[1], ($o[2] << 8) + $o[3]);
	}

	my @parts;
	if ($ip =~ /::/) {
		my ($left, $right) = split /::/, $ip, 2;
		my @l = length($left)  ? split(/:/, $left)  : ();
		my @r = length($right) ? split(/:/, $right) : ();
		my $missing = 8 - (@l + @r);
		return unless $missing >= 0;
		@parts = (@l, (('0') x $missing), @r);
	} else {
		@parts = split /:/, $ip;
		return unless @parts == 8;
	}

	return unless @parts == 8;
	for (@parts) {
		return unless /^[0-9A-Fa-f]{0,4}$/;
		$_ = sprintf "%04x", hex($_ || 0);
	}

	return @parts;
}

sub _ip_sort_key {
	my ($cidr) = @_;
	return unless defined $cidr;

	my ($ip, $mask) = split m{/}, $cidr, 2;

	if ($ip =~ /:/) {
		$mask //= 128;
		my @g = _expand_ipv6($ip);
		return (6, join(':', @g), $mask) if @g;
		return (9, $ip, $mask);
	} else {
		$mask //= 32;
		my @o = split /\./, $ip;
		if (@o == 4 && !grep { $_ !~ /^\d+$/ || $_ < 0 || $_ > 255 } @o) {
			return (4, sprintf("%03d.%03d.%03d.%03d", @o), $mask);
		}
		return (9, $ip, $mask);
	}
}

sub _cmp_cidr {
	my ($a_fam, $a_key, $a_mask) = _ip_sort_key($a);
	my ($b_fam, $b_key, $b_mask) = _ip_sort_key($b);

	return $a_fam <=> $b_fam
		|| $a_key cmp $b_key
		|| $a_mask <=> $b_mask;
}

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->remotecmd;

# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 6;
return (1, q{Please install Net::CIDR::Lite or libnet-cidr-lite-perl to use this command}) unless $DXCIDR::active;

my @out;
my @added;
my @in = split /\s+/, $line;
my $maxlth = 0;
my $width = $self->width // 80;
my $count = 0;

#$DB::single = 1;

# query
if (@in) {
	foreach my $ip (@in) {
		if (DXCIDR::find($ip)) {
			push @out, "$ip DIRTY";
			++$count;
		} else {
			push @out, "$ip CLEAN";
		}
	}
	return (1, @out);
} else {

	# list
	my @list = map {
		my $s = $_;
		$s =~ s!/(?:32|128)$!!;
		$maxlth = length $s if length $s > $maxlth;
		$s =~ /^1$/ ? undef : $s;
	} sort _cmp_cidr DXCIDR::list();

	my @l;
	$maxlth ||= 20;
	my $n = int($width / ($maxlth + 1));
	$n = 1 if $n < 1;

	my $format = "\%-${maxlth}s " x $n;
	chop $format;

	foreach my $list (@list) {
		next unless defined $list;
		++$count;

		if (@l >= $n) {
			push @out, sprintf $format, @l;
			@l = ();
		}

		push @l, $list;
	}

	if (@l) {
		push @l, "" while @l < $n;
		push @out, sprintf $format, @l;
	}
}

push @out, "show/badip: $count records found";
return (1, @out);
