package MyPageKit;

# $Id: MyPageKit.pm,v 1.7 2000/08/24 18:02:04 tjmather Exp $

use strict;

use vars qw(@ISA);
@ISA = qw(Apache::PageKit);

use Apache::Constants qw(OK REDIRECT DECLINED);

# form profiles for FormValidator
my $input_profile 
  = {
     newacct2 => {
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
		 },
    };

sub handler {

  # this line should be replaced with a DBI->connect(...) statement
  my $dbh = DBI->connect("DBI:driver:db:host","username","password");

  my $pk = MyPageKit->new(
			  form_validator_input_profile => $input_profile,
			  login_page => 'login1',
			  page_dispatch_prefix => 'MyPageKit::PageCode',
			  module_dispatch_prefix => 'MyPageKit::ModuleCode',
			  uri_prefix => 'pagekit/',
			  view_cache => 'normal',
			  session_handler_class => 'Apache::Session::MySQL',
			  dbh => $dbh,
			  session_args => {
					   Handle => $dbh,
					   LockHandle => $dbh,
					   IDLength => 8,
					  }
			 );

  my $status_code = $pk->prepare_page;
  return $status_code unless $status_code eq OK;

  # put code that is common to all pages here
  # begin EXAMPLE code
  my $view = $pk->{view};
  my $session = $pk->{session};
  $view->param(link_color => $session->{'link_color'} || 'ff9933');
  $view->param(text_color => $session->{'text_color'} || '000000');
  $view->param(bgcolor => $session->{'bgcolor'} || 'dddddd');
  $view->param(mod_color => $session->{'mod_color'} || 'ffffff');
  # end EXAMPLE code

  $pk->prepare_view;  
  $pk->print_view;

  return $status_code;
}

sub auth_credential {
  my ($pk, @credentials) = @_;
  my $dbh = $pk->{dbh};
  my $login = $credentials[0];
  my $passwd = $credentials[1];

  unless ($login ne "" && $passwd ne ""){
    $pk->message("You did not fill all of the fields.  Please try again.",
		 is_error => 1);
    return;
  }
  my $epasswd = crypt $passwd, "pk";

  my $sql_str = "SELECT user_id, ENCRYPT(passwd, '$epasswd') FROM pkit_user WHERE login=?";

  my ($user_id, $dbpasswd) = $dbh->selectrow_array($sql_str, {}, $login);

  unless ($epasswd eq $dbpasswd){
    $pk->message("Your login/password is invalid. Please try again.",
		is_error => 1);
    return;
  }

  my $secret_md5 = $pk->{secret_md5};

  my $hash = Digest::MD5->md5_hex(join ':', $secret_md5, $user_id, $epasswd);

  my $ses_key = {
		 'user_id'   => $user_id,
		 'hash'    => $hash
		};

  return $ses_key;
}

sub auth_session_key {
  my ($pk, $ses_key) = @_;

  my $apr = $pk->{apr};
  my $dbh = $pk->{dbh};
  my $view = $pk->{view};

  my $secret_md5 = $pk->{secret_md5};

  my $user_id = $ses_key->{user_id};

  my $sql_str = "SELECT login, ENCRYPT(passwd, 'pk'), pkit_admin FROM pkit_user WHERE user_id=?";

  my ($login, $epasswd, $pkit_admin) = $dbh->selectrow_array($sql_str,{},$user_id);

  # create a new hash and verify that it matches the supplied hash
  # (prevents tampering with the cookie)
  my $newhash = Digest::MD5->md5_hex(join ':', $secret_md5, $user_id, $epasswd);

  return unless $newhash eq $ses_key->{'hash'};

  $view->param('pkit_admin',$pkit_admin);
  $view->param('pkit_login',$login);

  return $user_id;
}

1;
