#
# set the logininfo option for users
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# Modify by kin EA3CV-2
# 20250310

my $self = shift;

return (0, $self->msg('e5')) if $self->priv < 8;

$self->user->wantlogininfo(1);
$self->logininfo(1);

return (1, $self->msg('ok'));
