package MyPageKit::Common;

# $Id: Common.pm,v 1.8 2001/05/16 02:56:15 tjmather Exp $

use strict;

use vars qw(@ISA);
@ISA = qw(Apache::PageKit::Model);

use Apache::Constants qw(OK REDIRECT DECLINED);

$__PACKAGE__::secret_md5 = 'you_should_place_your_own_md5_string_here';

use DBI;
use MyPageKit::MyModel;
use Digest::MD5;

sub pkit_dbi_connect {
  # this line should be replaced with a DBI->connect(...) statement
  # for your database
  return DBI->connect("DBI:CSV:f_dir=/tmp/csvdb")
	|| die "$DBI::errstr";
}

sub pkit_session_setup {
  # uncomment if you need use a $dbh object in your session setup
  #my $model = shift;
  #my $dbh = $model->dbh;

  my %session_setup = (
		       session_store_class => 'File',
		       session_lock_class => 'File',
		       session_args => {
#					Handle => $dbh,
#					LockHandle => $dbh,
					Directory => '/tmp/pkit_sessions',
					LockDirectory => '/tmp/pkit_sessions_lock',
				       }
		      );
  return \%session_setup;
}

sub pkit_common_code {
  my $model = shift;

  # put code that is common to all pages here
  my $session = $model->session;

  # for the pagekit.org website, we control the colors based on the
  # values the user selected, stored in the session.
  $model->output(link_color => $session->{'link_color'} || 'ff9933');
  $model->output(text_color => $session->{'text_color'} || '000000');
  $model->output(bgcolor => $session->{'bgcolor'} || 'dddddd');
  $model->output(mod_color => $session->{'mod_color'} || 'ffffff');
}

sub pkit_auth_credential {
  my ($model) = @_;
  my $dbh = $model->dbh;
  my $login = $model->input('login');
  my $passwd = $model->input('passwd');

  unless ($login ne "" && $passwd ne ""){
    $model->pkit_message("You did not fill all of the fields.  Please try again.",
		 is_error => 1);
    return;
  }
  my $epasswd = crypt $passwd, "pk";

  my $sql_str = "SELECT user_id, passwd FROM pkit_user WHERE login=?";

  my ($user_id, $dbpasswd) = $dbh->selectrow_array($sql_str, {}, $login);

  unless ($epasswd eq crypt($dbpasswd,$epasswd)){
    $model->pkit_message("Your login/password is invalid. Please try again.",
		is_error => 1);
    return;
  }

  my $hash = Digest::MD5->md5_hex(join ':', $__PACKAGE__::secret_md5, $user_id, $epasswd);

  my $ses_key = {
		 'user_id'   => $user_id,
		 'hash'    => $hash
		};

  return $ses_key;
}

sub pkit_auth_session_key {
  my ($model, $ses_key) = @_;

  my $dbh = $model->dbh;

  my $user_id = $ses_key->{user_id};

  my $sql_str = "SELECT login, passwd FROM pkit_user WHERE user_id=?";

  my ($login, $epasswd) = $dbh->selectrow_array($sql_str,{},$user_id);

  # create a new hash and verify that it matches the supplied hash
  # (prevents tampering with the cookie)
  my $newhash = Digest::MD5->md5_hex(join ':', $__PACKAGE__::secret_md5, $user_id, crypt($epasswd,"pk"));

  return unless $newhash eq $ses_key->{'hash'};

  $model->output(pkit_user => $user_id);

  $model->output('pkit_login',$login);

  return $user_id;
}

1;

__END__

=head1 NAME

MyPageKit::Common - Model class containing code common across site.

=head1 DESCRIPTION

This class contains methods that are common across the site, such
as authentication and session key generation.  This particular class
is an example class that is used for the pagekit.org website.
It is derived from Apache::PageKit::Model and a base class for
the Model classes for the pagekit.org site.
In general, the class hierarchy should look like:

		+---------------------------------------+
		| 	  Apache::PageKit::Model	|
		| Model code that provides an interface	|
		| to PageKit and is common to all sites |
		+---------------------------------------+
				     |
		+---------------------------------------+
		|	    MyPageKit::Common		|
		| Model code that is particular to the  |
		| site, but common across all pages     |
		+---------------------------------------+
			/	    |		\
    +----------------------------+     +----------------------------+
    | MyPageKit::YourClass1      |     | MyPageKit::YourClassN      |
    | Model code that is for a   | ... | Model code that is for a   |
    | group of pages on the site |     | group of pages on the site |
    +----------------------------+     +----------------------------+

It is a good starting point for building your own base class for your
Model classes.

=head1 METHODS

These are the methods that your should implement in your own MyPageKit::Common
class:

=over 4

=item pkit_dbi_connect

Should return a L<DBI> database handler object (C<$dbh>).  This
object can be accessed from the rest of the Model by the method
C<$model-E<gt>dbh>.

=item pkit_session_setup

Should return a hash reference with three key/value pairs:

  * session_store_class
	The object store class that should be used for
	L<Apache::PageKit::Session> session handling.
  * session_lock_class
	The lock manager class that should be used for
	L<Apache::PageKit::Session> session handling.
  * session_args
	Reference to an hash containing options for the
	C<session_lock_class> and C<session_store_class>.

=item pkit_auth_credential

Should verify the user-supplied credentials and return a session key.  The
session key can be any string - often you'll use the user ID and
a MD5 hash of a a secret key, user ID, password.

=item pkit_auth_session_key

Should verify the session key (previously generated by C<auth_credential>)
and return the user ID.

=item pkit_common_code

Executes code that is common across your site.

=back

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 COPYRIGHT

Copyright (c) 2000, AnIdea, Corp.  All rights Reserved.  PageKit is a trademark
of AnIdea Corp.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program;
if not, obtain one at http://www.pagekit.org/license
