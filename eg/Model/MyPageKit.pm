package MyPageKit;

# $Id: MyPageKit.pm,v 1.6 2001/01/01 00:38:07 tjmather Exp $

use strict;

use vars qw(@ISA);
@ISA = qw(Apache::PageKit);

use Apache::Constants qw(OK REDIRECT DECLINED);

$Apache::PageKit::secret_md5 = 'you_should_place_your_own_md5_string_here';

use DBI;
use MyPageKit::MyModel;

sub handler {
  my $r = shift;

  # this line should be replaced with a DBI->connect(...) statement
  my $dbh = DBI->connect("DBI:CSV:f_dir=/tmp/csvdb");

  my $pk = MyPageKit->new(
			  session_store_class => 'File',
			  session_lock_class => 'File',
			  dbh => $dbh,
			  session_args => {
					Directory => '/tmp/pkit_sessions',
					LockDirectory => '/tmp/pkit_sessions_lock',
					  }
			 );

  my $status_code = $pk->prepare_page;
  return $status_code unless $status_code eq OK;

  # put code that is common to all pages here
  # begin EXAMPLE code
  my $model = $pk->{model};
  my $session = $model->{session};
  $model->output_param(link_color => $session->{'link_color'} || 'ff9933');
  $model->output_param(text_color => $session->{'text_color'} || '000000');
  $model->output_param(bgcolor => $session->{'bgcolor'} || 'dddddd');
  $model->output_param(mod_color => $session->{'mod_color'} || 'ffffff');
  # end EXAMPLE code

  $pk->prepare_view;
  $pk->print_view;

  return $status_code;
}

sub auth_credential {
  my ($pk, @credentials) = @_;
  my $model = $pk->{model};
  my $dbh = $model->{dbh};
  my $login = $credentials[0];
  my $passwd = $credentials[1];

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

  my $hash = Digest::MD5->md5_hex(join ':', $Apache::MyPageKit::secret_md5, $user_id, $epasswd);

  my $ses_key = {
		 'user_id'   => $user_id,
		 'hash'    => $hash
		};

  return $ses_key;
}

sub auth_session_key {
  my ($pk, $ses_key) = @_;

  my $model = $pk->{model};
  my $dbh = $model->{dbh};

  my $user_id = $ses_key->{user_id};

  my $sql_str = "SELECT login, passwd FROM pkit_user WHERE user_id=?";

  my ($login, $epasswd) = $dbh->selectrow_array($sql_str,{},$user_id);

  # create a new hash and verify that it matches the supplied hash
  # (prevents tampering with the cookie)
  my $newhash = Digest::MD5->md5_hex(join ':', $Apache::MyPageKit::secret_md5, $user_id, crypt($epasswd,"pk"));

  return unless $newhash eq $ses_key->{'hash'};

  $model->output_param('pkit_login',$login);

  return $user_id;
}

1;

__END__

=head1 NAME

MyPageKit - Example subclass for pagekit.org website

=head1 DESCRIPTION

This is included to provide a example of a Apache::PageKit subclass.

It is also the code behind the http://www.pagekit.org/ web site.

It is a good starting point for building your own subclass.

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
