package MyPageKit::MyModel;

# $Id $

use vars qw(@ISA);
@ISA = qw(MyPageKit::Common);

use strict;

# customize site look-and-feel
sub customize {
  my $model = shift;
  my $session = $model->session;
  my $change_flag;
  for ($model->input_param){
    $session->{$_} = $model->input_param($_);
    $change_flag = 1;
  }
  $model->pkit_message("Your changes have been made.") if $change_flag;
}

sub newacct2 {
  my $model = shift;

  my $dbh = $model->dbh;

  my $input_profile = {
		  required => [ qw( pkit_model email login passwd1 passwd2 ) ],
		  constraints => {
				  email => "email",
				  login => { constraint => sub {
					       my ($new_login, $model) = @_;
					       my $dbh = $model->dbh;

					       # check to make sure login isn't already used
					       my $sql_str = "SELECT login FROM pkit_user WHERE login = ?";
					       # login is used, return false
					       return 0 if $dbh->selectrow_array($sql_str,{},$new_login);
					       # login isn't used, return true
					       return 1;
					     },
					     params => [ qw( login pkit_model )]
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
			       passwd1 => "The passwords you entered do not match.",
			      },
		 };
  # validate user input
  unless($model->pkit_validate_input($input_profile)){
    $model->pkit_set_page_id('newacct1');
    return;
  }

  # make up userID
  my $user_id = substr(MD5->hexhash(MD5->hexhash(time(). {}. rand(). $$)), 0, 8);

  my $sql_str = "INSERT INTO pkit_user (user_id,email,login,passwd) VALUES (?,?,?,?)";
  $dbh->do($sql_str, {}, $user_id, $model->input_param('email'),
				$model->input_param('login'),
				$model->input_param('passwd1'));

  $model->input_param('pkit_credential_0', $model->input_param('login'));
  $model->input_param('pkit_credential_1', $model->input_param('passwd1'));
  $model->input_param('pkit_remember', 'on');
}

1;

__END__

=head1 NAME

MyPageKit::MyModel - Example Derived Model Class implementing Backend Code for pagekit.org website

=head1 DESCRIPTION

This module provides a example of a Derived Model component
(Business Logic) of a PageKit website.

It is also the code used for the http://www.pagekit.org/ web site.  It contains
two methods, one for customizing the look and feel for the website, and
another for processing new account sign ups.

It is a good starting point for building your backend for your PageKit website.

=head1 AUTHOR

T.J. Mather (tjmather@thoughtstore.com)

=head1 COPYRIGHT

Copyright (c) 2000, AnIdea Corp.  All rights Reserved.  PageKit is a trademark
of AnIdea, Corp.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program;
if not, obtain one at http://www.pagekit.org/license
