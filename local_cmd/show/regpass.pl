#
# show/regpass
#
# Show registered/password status.
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

$line //= '';
$line =~ s/[^\w\-\/\s]+//g;
$line = uc($line);

my @out = $self->spawn_cmd("show/regpass $line", sub {
	my @out;
	my @rows;

	require DBI;
	my $dbh = DBI->connect(
		"dbi:mysql:database=$main::mysql_db;host=$main::mysql_host",
		$main::mysql_user,
		$main::mysql_pass,
		{ RaiseError => 1, AutoCommit => 1, mysql_enable_utf8mb4 => 1 }
	);

	my $sql;
	my @bind;

	if ($line && $line ne 'ALL') {
		my @calls = split /\s+/, $line;
		my $placeholders = join ',', ('?') x @calls;
		$sql = "SELECT `call`, `registered`, `passwd` FROM `users` WHERE `call` IN ($placeholders) ORDER BY `call`";
		@bind = @calls;
	} elsif ($line eq 'ALL') {
		$sql = "SELECT `call`, `registered`, `passwd` FROM `users` ORDER BY `call`";
	} else {
		$sql = "SELECT `call`, `registered`, `passwd` FROM `users`
		        WHERE `registered` = 1 OR (`passwd` IS NOT NULL AND `passwd` <> '')
		        ORDER BY `call`";
	}

	my $sth = $dbh->prepare($sql);
	$sth->execute(@bind);

	push @out, sprintf "%-10s %-4s %-4s", "Call", "Reg", "Pass";
	push @out, sprintf "%-10s %-4s %-4s", "--------", "---", "----";

	my $count = 0;
	while (my ($call, $reg, $passwd) = $sth->fetchrow_array) {
		push @out, sprintf "%-10s %-4s %-4s",
			$call,
			$reg ? 'ON' : 'OFF',
			(defined($passwd) && length($passwd)) ? 'ON' : 'OFF';
		$count++;
	}

	$dbh->disconnect;

	push @out, "Total users listed: $count";
	push @out, "Use: sh/regpass <call> for one user, sh/regpass for registered/password users, sh/regpass all for full list.";
	return @out;
});

return (1, @out);
