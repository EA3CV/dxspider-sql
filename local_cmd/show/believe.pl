#
# show/believe - Display the list of nodes a given node believes
#
# Usage:
#   show/believe <node>
#   show/believe            # (shows all nodes with believes)
#
# Shows the believe list for a node, or all believe lists if no node given.
#

my ($self, $line) = @_;
my $node = uc $line;
my @out;

return (1, $self->msg('e5')) if $self->priv < 6;

if ($node) {
    return (1, $self->msg('e22', $node)) unless is_callsign($node);
    my $user = DXUser::get_current($node);
    return (1, $self->msg('e13', $node)) unless $user->is_node;

    my %seen;
    my @believes = grep { !$seen{$_}++ } $user->believe;

    if (@believes) {
        push @out, "$node: " . join(' ', sort @believes);
    } else {
        push @out, "$node: (none)";
    }
    return (1, @out);
}

# Mostrar todos los nodos con believes
my @calls = DXUser::get_all_calls;
my @lines;

foreach my $c (sort @calls) {
    my $u = DXUser::get_current($c);
    next unless $u && $u->is_node;

    my %seen;
    my @believes = grep { !$seen{$_}++ } $u->believe;
    next unless @believes;

    push @lines, "$c: " . join(' ', sort @believes);
}

push @out, @lines ? ("List of all believes set by nodes:", @lines)
                  : ("No nodes have any believes set.");

return (1, @out);
