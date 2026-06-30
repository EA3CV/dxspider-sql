#
# make_wcy.pl - DXSpider internal command
#
# Put in:
#   /spider/local_cmd/make_wcy.pl
#
# Usage:
#   make_wcy
#
# DXSpider cron:
#   30 * * * * run_cmd('make_wcy')
#
# Sources:
#   K       -> NOAA current Kp, fallback HamQSL K
#   expK    -> NOAA Kp forecast, fallback K
#   A       -> HamQSL A index
#   R       -> HamQSL sunspots
#   SFI     -> HamQSL solarflux
#   SA      -> HamQSL X-Ray class, fallback calculated from SFI
#   GMF     -> HamQSL geomagnetic field, fallback calculated from K
#   Aurora  -> HamQSL aurora, fallback calculated from K
#

my ($self, $line) = @_;

use strict;
use warnings;
use JSON::PP;
use HTTP::Tiny;

my $ua = HTTP::Tiny->new(
    timeout => 20,
    agent   => 'DXSpider-WCY/1.0'
);

sub get_json {
    my ($url) = @_;
    my $r = $ua->get($url);
    die "GET $url failed: $r->{status} $r->{reason}\n" unless $r->{success};
    return decode_json($r->{content});
}

sub get_text {
    my ($url) = @_;
    my $r = $ua->get($url);
    die "GET $url failed: $r->{status} $r->{reason}\n" unless $r->{success};
    return $r->{content};
}

sub xml_tag {
    my ($xml, $tag) = @_;
    return undef unless defined $xml;
    return $1 if $xml =~ m{<$tag>\s*<!\[CDATA\[(.*?)\]\]>\s*</$tag>}is;
    return $1 if $xml =~ m{<$tag>\s*(.*?)\s*</$tag>}is;
    return undef;
}

sub round_int {
    my $v = shift;
    return undef unless defined $v;
    $v =~ s/^\s+|\s+$//g;
    return undef if $v eq '';
    return int($v + 0.5);
}

sub first_value {
    my ($href, @keys) = @_;
    return undef unless ref($href) eq 'HASH';

    for my $k (@keys) {
        return $href->{$k}
            if exists $href->{$k}
            && defined $href->{$k}
            && $href->{$k} ne '';
    }

    return undef;
}

sub calc_gmf {
    my $k = shift || 0;

    return 'qui' if $k <= 1;
    return 'act' if $k <= 3;
    return 'min' if $k == 4;
    return 'maj' if $k == 5;
    return 'sev' if $k == 6;
    return 'mag';
}

sub calc_au {
    my $k = shift || 0;

    return 'strong' if $k >= 7;
    return 'aurora' if $k >= 5;
    return 'no';
}

sub calc_sa {
    my $sf = shift || 0;

    return 'qui' if $sf < 100;
    return 'eru' if $sf < 150;
    return 'act' if $sf < 200;
    return 'maj' if $sf < 250;
    return 'pro' if $sf < 300;
    return 'war';
}

my ($k, $expk, $a, $sf, $r);
my ($sa, $gmf, $au);

#
# NOAA: K and expected K
#

eval {
    my $kp = get_json('https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json');
    my $last = $kp->[-1];

    if (ref($last) eq 'HASH') {
        $k = round_int(first_value($last, qw(Kp kp planetary_kindex planetary_k_index)));
    }
};

eval {
    my $forecast = get_json('https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json');

    foreach my $row (@$forecast) {
        next unless ref($row) eq 'HASH';

        my $v = first_value($row, qw(kp Kp planetary_kindex planetary_k_index));
        next unless defined $v;

        $expk = round_int($v);
        last;
    }
};

#
# HamQSL: operational SFI, A, R, SA, GMF, Aurora
#

eval {
    my $xml = get_text('https://www.hamqsl.com/solarxml.php');

    my $hk  = xml_tag($xml, 'kindex');
    my $ha  = xml_tag($xml, 'aindex');
    my $hr  = xml_tag($xml, 'sunspots');
    my $hsf = xml_tag($xml, 'solarflux');

    $k  = round_int($hk)  if !defined($k) && defined $hk;
    $a  = round_int($ha)  if defined $ha;
    $r  = round_int($hr)  if defined $hr;
    $sf = round_int($hsf) if defined $hsf;

    my $geomag = lc(xml_tag($xml, 'geomagfield') || '');

    if    ($geomag =~ /quiet/)     { $gmf = 'qui'; }
    elsif ($geomag =~ /unsettled/) { $gmf = 'act'; }
    elsif ($geomag =~ /active/)    { $gmf = 'min'; }
    elsif ($geomag =~ /minor/)     { $gmf = 'min'; }
    elsif ($geomag =~ /major/)     { $gmf = 'maj'; }
    elsif ($geomag =~ /severe/)    { $gmf = 'sev'; }
    elsif ($geomag =~ /storm/)     { $gmf = 'maj'; }
    elsif ($geomag =~ /mag/)       { $gmf = 'mag'; }

    my $aurora = xml_tag($xml, 'aurora');

    if (defined $aurora) {
        $aurora =~ s/^\s+|\s+$//g;

        if    ($aurora =~ /strong/i) { $au = 'strong'; }
        elsif ($aurora =~ /aurora/i) { $au = 'aurora'; }
        elsif ($aurora =~ /^yes$/i)  { $au = 'aurora'; }
        elsif ($aurora =~ /^no$/i)   { $au = 'no'; }
        elsif ($aurora =~ /^\d+$/) {
            if    ($aurora >= 50) { $au = 'strong'; }
            elsif ($aurora > 10)  { $au = 'aurora'; }
            else                  { $au = 'no'; }
        }
    }

    my $xray = lc(xml_tag($xml, 'xray') || '');

    if    ($xray =~ /^a/) { $sa = 'qui'; }
    elsif ($xray =~ /^b/) { $sa = 'eru'; }
    elsif ($xray =~ /^c/) { $sa = 'act'; }
    elsif ($xray =~ /^m/) { $sa = 'maj'; }
    elsif ($xray =~ /^x/) { $sa = 'pro'; }
};

$k    = 0 unless defined $k;
$a    = 0 unless defined $a;
$r    = 0 unless defined $r;
$sf   = 0 unless defined $sf;
$expk = $k unless defined $expk;

$sa  = calc_sa($sf) unless defined $sa;
$gmf = calc_gmf($k) unless defined $gmf;
$au  = calc_au($k)  unless defined $au;

my $args = sprintf(
    "k=%d,expk=%d,a=%d,r=%d,sf=%d,sa=%s,gmf=%s,au=%s",
    int($k),
    int($expk),
    int($a),
    int($r),
    int($sf),
    $sa,
    $gmf,
    $au
);

return $self->run_cmd("wcy $args");
