#
# show/registered
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = uc($line);
}

@out = $self->spawn_cmd("show/registered $line", sub {
	my @out;
	my @val;
	my $count = 0;

	if ($line) {
		my $u = DXUser::get($line);
		if ($u) {
			my $r = $u->registered // 0;
			my $status = ($r eq '1') ? "Registered" : "Not registered";
			push @val, "$line ($status)";
			$count = 1;
		} else {
			push @val, "$line (User not found)";
		}
	} else {
		my @calls;
		require DBI;
		my $dbh = DBI->connect(
			"dbi:mysql:database=$main::mysql_db;host=$main::mysql_host",
			$main::mysql_user, $main::mysql_pass,
			{ RaiseError => 1, AutoCommit => 1 }
		);

		my $sth = $dbh->prepare("SELECT `call` FROM `users` WHERE `registered` = '1'");
		$sth->execute();
		while (my ($call) = $sth->fetchrow_array) {
			push @calls, $call;
		}
		$dbh->disconnect;

		for my $call (@calls) {
			my $u = DXUser::get($call);
			next unless $u;
			my $r = $u->registered // 0;
			if ($r eq '1') {
				push @val, "$call (Registered)";
				$count++;
			}
		}
	}

	my @l;
	foreach my $entry (@val) {
		if (@l >= 3) {
			push @out, sprintf "%-25s %-25s %-25s", @l;
			@l = ();
		}
		push @l, $entry;
	}
	if (@l) {
		push @l, "" while @l < 3;
		push @out, sprintf "%-25s %-25s %-25s", @l;
	}

	push @out, "Total users listed: $count";
	return @out;
});

return (1, @out);
