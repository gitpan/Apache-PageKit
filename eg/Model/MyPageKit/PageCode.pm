package MyPageKit::PageCode;

# $Id: PageCode.pm,v 1.3 2000/12/23 07:08:37 tjmather Exp $

use strict;

# customize site look-and-feel
sub page_customize {
  my $pk = shift;
  my $apr = $pk->{apr};
  my $session = $pk->{session};
  my $change_flag;
  for ($apr->param){
    $session->{$_} = $apr->param($_);
    $change_flag = 1;
  }
  $pk->message("Your changes have been made.") if $change_flag;
}

sub page_newacct2 {
  my $pk = shift;

  my $dbh = $pk->{dbh};
  my $apr = $pk->{apr};
  my $model = $pk->{model};

  my $input_profile = {
		  required => [ qw( pkit_object email login passwd1 passwd2 ) ],
		  constraints => {
				  email => "email",
				  login => { constraint => sub {
					       my ($new_login, $pk) = @_;
					       my $dbh = $pk->{dbh};
					       my $user_id = $pk->{apr}->connection->user;
					       my $sql_str = "SELECT login FROM pkit_user WHERE user_id=?";
					       my ($old_login) = $dbh->selectrow_array($sql_str,{},$user_id);

					       # return ok if user didn't change login
					       # (assumes that login is case-insensitive)
					       return 1 if lc($old_login) eq lc($new_login);

					       # user changed login, check to make sure it isn't used
					       $sql_str = "SELECT login FROM pkit_user WHERE login = ?";
					       # login is used, return false
					       return 0 if $dbh->selectrow_array($sql_str,{},$new_login);
					       # login isn't used, return true
					       return 1;
					     },
					     params => [ qw( login pkit_object )]
					   },
				  passwd1 => { constraint => sub { return $_[0] eq $_[1]; },
					       params => [ qw( passwd1 passwd2 ) ]
					     },
				  passwd2 => { constraint => sub { return $_[0] eq $_[1]; },
					       params => [ qw( passwd1 passwd2 ) ]
					     },
				 },
		  messages => {
			       login => "The login, <b>%%VALUE%%</b>, has already been used.",
			       email => "The E-mail address, <b>%%VALUE%%</b>, is invalid.",
			       phone => "The phone number you entered is invalid.",
			       passwd1 => "The passwords you entered do not match."
			      },
		 };
  # validate user input
  unless($model->validate_input($input_profile)){
    $pk->continue('newacct1');
    return;
  }

  # make up userID
  my $user_id = substr(MD5->hexhash(MD5->hexhash(time(). {}. rand(). $$)), 0, 8);

  my $sql_str = "INSERT INTO pkit_user (user_id,email,login,passwd) VALUES (?,?,?,?)";
  $dbh->do($sql_str, {}, $user_id, $apr->param('email'), $apr->param('login'), $apr->param('passwd1'));

  $apr->param('pkit_credential_0', $apr->param('login'));
  $apr->param('pkit_credential_1', $apr->param('passwd1'));
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
