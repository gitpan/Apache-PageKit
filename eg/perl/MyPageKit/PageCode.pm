package MyPageKit::PageCode;

# $Id: PageCode.pm,v 1.3 2000/08/29 04:18:31 tjmather Exp $

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

__END__

=head1 NAME

MyPageKit::PageCode - Example Backend Code for pagekit.org website

=head1 DESCRIPTION

This module provides a example of the Model component (Business Logic) of a
PageKit website.

It is also the code used for the http://www.pagekit.org/ web site.  It contains
two methods, one for customizing the look and feel for the website, and
another for processing new account sign ups.

It is a good starting point for building your backend for your PageKit website.

=head1 AUTHOR

T.J. Mather (tjmather@thoughtstore.com)

=head1 COPYRIGHT

Copyright (c) 2000, ThoughtStore, Inc.  All rights Reserved.  PageKit is a trademark
of ThoughtStore, Inc.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program;
if not, obtain one at http://www.pagekit.org/license
