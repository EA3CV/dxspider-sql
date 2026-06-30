#!/usr/bin/perl

#
# Bot that sends the total of nodes/users
# via Telegram
#
# Usage: bot_stad.pl <server>
# eg     bot_stad.pl EA3CV-2
#
# Created by Kin EA3CV
# ea3cv@cronux.net
#
# v0.0a
# 20201016
#

use strict;
use warnings;
use 5.10.1;

my ($self, $server) = @_;

my $all_users = scalar DXChannel::get_all_users();
my $all_nodes = scalar DXChannel::get_all_nodes();

telegram($server, "Nodos: $all_nodes", "Users: $all_users");

sub telegram {
        my $srv = shift;
        my $nodes = shift;
        my $users = shift;

        my $token = "1376233105:AAHOfU_M97j1gXm1l4xLPpmF_v6CYCxIL3M";
        my $id = "1089814914";
        my $url = "https://api.telegram.org/bot$token/sendMessage";
        `curl -s -X POST $url -d chat_id=$id -d text="$srv\n $nodes $users\n"`;
}
