package MyPageKit::PageCode;

# $Id: PageCode.pm,v 1.1 2000/08/19 02:12:05 tjmather Exp $

use strict;

# customize site look-and-feel
sub page_customize {
  my $pk = shift;
  my $apr = $pk->{apr};
  my $session = $pk->{session};
  for ($apr->param){
    $session->{$_} = $apr->param($_);
  }
  $pk->message("Your changes have been made.");
}

sub page_newacct2 {
  my $pk = shift;

  my $dbh = $pk->{dbh};
  my $apr = $pk->{apr};

  # get validated data
  my $fdat = $pk->{fdat} || warn "no validated data";

  my $sql_str = "INSERT INTO pkit_user (email,login,passwd) VALUES (?,?,?)";
  $dbh->do($sql_str, {}, $fdat->{email}, $fdat->{login}, $fdat->{passwd1});

  $apr->param('pkit_credential_0', $fdat->{'login'});
  $apr->param('pkit_credential_1', $fdat->{'passwd1'});
  $apr->param('pkit_remember', 'on');
}

1;
