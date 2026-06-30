#
# show/regpass
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

if ($line) {
	$line =~ s/[^\w\-\/\s]+//g;
	$line = uc($line);
}

@out = $self->spawn_cmd("show/regpass $line", sub {
	my @out;
	my @val;
	my $count = 0;

	require DBI;
	my $dbh = DBI->connect(
		"dbi:mysql:database=$main::mysql_db;host=$main::mysql_host",
		$main::mysql_user, $main::mysql_pass,
		{ RaiseError => 1, AutoCommit => 1, mysql_enable_utf8mb4 => 1 }
	);

	if ($line) {
		my @calls = split /\s+/, $line;
		my $sth = $dbh->prepare("SELECT `call`, `registered`, `passwd` FROM `users` WHERE `call` = ?");
		for my $call (@calls) {
			$sth->execute($call);
			if (my ($c, $reg, $passwd) = $sth->fetchrow_array) {
				push @val, sprintf "%-10s %-4s %-4s",
					$c,
					$reg ? 'ON' : 'OFF',
					(defined($passwd) && length($passwd)) ? 'ON' : 'OFF';
				$count++;
			} else {
				push @val, sprintf "%-10s %-4s %-4s", $call, 'NF', 'NF';
			}
		}
	} else {
		my $sth = $dbh->prepare("
			SELECT `call`, `registered`, `passwd`
			FROM `users`
			WHERE `registered` = 1
			   OR (`passwd` IS NOT NULL AND `passwd` <> '')
			ORDER BY `call`
		");
		$sth->execute();

		while (my ($call, $reg, $passwd) = $sth->fetchrow_array) {
			push @val, sprintf "%-10s %-4s %-4s",
				$call,
				$reg ? 'ON' : 'OFF',
				(defined($passwd) && length($passwd)) ? 'ON' : 'OFF';
			$count++;
		}
	}

	$dbh->disconnect;

	push @out, sprintf "%-10s %-4s %-4s", "Call", "Reg", "Pass";
	push @out, sprintf "%-10s %-4s %-4s", "--------", "---", "----";
	push @out, @val;
	push @out, "Total users listed: $count";

	return @out;
});

return (1, @out);
