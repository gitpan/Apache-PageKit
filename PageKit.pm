package Apache::PageKit;

# $Id: PageKit.pm,v 1.32 2000/08/24 19:21:53 tjmather Exp $

# CPAN Modules required for pagekit
use Apache::URI ();
use Apache::Cookie ();
use Apache::Request ();
use Apache::Session ();
use Apache::Util ();
use HTML::FillInForm ();
use HTML::FormValidator ();
use HTML::Parser ();
use HTML::Template ();
use Mail::Mailer ();
use URI::Escape ();

# PageKit modules
use Apache::PageKit::Info ();
use Apache::PageKit::View ();
use Apache::PageKit::Error ();
use Apache::PageKit::FormValidator ();

use strict;

use Apache::Constants qw(OK REDIRECT DECLINED);

use vars qw($VERSION %info_hash);
$VERSION = '0.01';

# we store info as a hash, key'ed on the virtual server
# this subroutine is called when a new child is initiated
sub _child_init {
  my $r = Apache->request;
  $info_hash{$r->dir_config("PKIT_PAGE_INFO_FILE")} = Apache::PageKit::Info->new();
}

sub _params_as_string {
  my ($apr) = @_;
  my $query_string = join ('&', map {$_ . "=" . $apr->param($_)} $apr->param);

  # for future use (such as logging stage)
  $apr->notes('query_string', $query_string);

  return join ('&', map {$_ ."=" . $apr->param($_)} grep !/^(pkit_logout|pkit_view)$/, $apr->param);
}

sub prepare_page {
  my $pk = shift;

  # $dbh is a DBI object
  my $dbh = $pk->{dbh};

  # $apr is an Apache::Request object
  my $apr = $pk->{apr};

  # $view is an Apache::PageKit::View object
  my $view = $pk->{view};

  # $info is an Apache::PageKit::Info object
  my $info = $pk->{info};

  # $validator is an Apache::PageKit::FormValidator object
  my $validator = $pk->{validator};

  my $query_string = _params_as_string($apr);

  # decline to serve images, etc
#  return DECLINED if $apr->content_type && $apr->content_type !~ m|^text/|io;

  my $uri = $apr->uri;

  # decline PKIT_FILES_MATCH
  if (my $files_match = $apr->dir_config('PKIT_FILES_MATCH')){
    return if $uri =~ m/$files_match/;
  }

  $uri =~ s(^/$pk->{uri_prefix})(/) if $pk->{uri_prefix};

  $pk->{page_id} = $uri;

  # get rid of leading forward slash
  $pk->{page_id} =~ s(^/+)();

  # add index for pageid with trailing slash "/"
  $pk->{page_id} =~ s!(.+)/$!$1/index!;

  # get default page (for domain) if there is no page in url
  # or if page_id has characters that are not in [a-zA-Z0-9_/-]
  unless($pk->{page_id} =~ m!^[\w/]+$!){
    $pk->{page_id} = $pk->get_default_page;
  }

  # redirect "not found" pages
  unless ($info->page_exists($pk->{page_id})){
    $pk->{page_id} = $info->page_id_match($pk->{page_id})
      || $pk->{not_found_page}
      || $pk->{default_page};
  }

  # validate data
  if ($validator && !$validator->validate($pk)){
    # invalid data, redirect to error_page
    if(my $page_id = $info->get_param('error_page')){
      $pk->{disable_code} = 1 if $info->get_param('error_page_run_code') ne 'yes';
      $pk->{page_id} = $page_id;
    } else {
      die "error_page not specified for page $pk->{page_id}";
    }
  }

  # new registration and edit profile requires special handling
  # the page code needs to be called _before_ the authenticate code runs
  if($info->get_param('new_credential') eq 'yes'){
    $pk->page_code unless $pk->{disable_code};
  }

  my $uri_with_query = $uri;
  my $pkit_selfurl;
  if($query_string){
    $uri_with_query .= "?" . $query_string;
    $pkit_selfurl = $uri_with_query . '&';
  } else {
    $pkit_selfurl = $uri_with_query . '?';
  }
  $view->param(PKIT_SELFURL => $pkit_selfurl);

  # make sure that we have a subdomain so cookies work
  # ie. redirect domain.tld -> www.domain.tld
  my $host = (split(':',$pk->{apr}->headers_in->{'Host'}))[0];
  if($host =~ m(^[^.]+\.[^.]+$)){
    $apr->headers_out->set(Location => 'http://www.' . $host . $uri_with_query);
    return REDIRECT;
  }

#  my $pkit_done = Apache::Util::escape_uri($apr->param('pkit_done') || $uri_with_query);
  my $pkit_done = URI::Escape::uri_escape($apr->param('pkit_done') || 'http://' . $host . $uri_with_query, '&?"');
  $view->param("pkit_done",$pkit_done);

  my $auth_user;

  my @credentials;
  while (my $credential = $apr->param("pkit_credential_" . ($#credentials + 1))){
    push @credentials, $credential;
  }

  # if crendential_0 field is present, user is attempting to log in
  if(defined $apr->param('pkit_credential_0')){
    if ($pk->login(@credentials)){
      # if login is sucessful, redirect to (re)set cookie
      return REDIRECT;
    } else {
      # else return to login form
#      my $referer = $apr->header_in('Referer');
#      $referer =~ s(http://[^/]*/([^?]*).*?)($1);
      $pk->{page_id} = $apr->param('pkit_login_page') || $pk->{login_page};
    }
  } elsif($apr->param('pkit_logout')){
    $pk->logout;
    $apr->param('pkit_check_cookie','');
    # goto home page when user logouts (if from page that requires login) 
    my $add_message = "";
    unless ($info->get_param('require_login') eq "no"){
      $pk->{page_id} = $pk->{login_page};
      $add_message = "You can log back in again below:";
    }
    $pk->message("You have sucessfully logged out.  $add_message");
  } else {
    $auth_user = $pk->authenticate;
  }

  if($auth_user){
    # user is logged in, display "log out" link

    my $link = $uri_with_query;

    $link =~ s/ /+/g;
    if ($link =~ /\?/){
      $link .= '&pkit_logout=yes';
    } else {
      $link .= '?pkit_logout=yes';
    }
    $view->param('pkit_loginout_link', $link);

    if ($info->get_param('require_login') eq 'recent' &&
	$pk->{session}->{last_activity} + $pk->{recent_login_timeout} < time()){
      # user is logged in, but has not been active recently

      # display verify password form
      $pk->{page_id} = $pk->{verify_page};
      # pkit_done parameter is used to return user to page that they orignally requested
      # after login is finished
      $apr->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");
    }
  } else {
    # user is not logged in, display "log in" link
    $view->param('pkit_loginout_link', qq{/$pk->{login_page}?pkit_done=$pkit_done});

    # check if cookies should be set
    if($apr->param('pkit_check_cookie') eq 'on'){
      # cookies should be set but aren't.
      if($pk->{cookies_not_set_page}){
	# display "cookies are not set" error page.
	$pk->{page_id} = $pk->{cookies_not_set_page};
      } else {
	# display login page with error message
	$pk->{page_id} = $pk->{login_page};
	$pk->message("Cookies must be enabled in your browser.",
		    is_error => 1);
      }
    }

    if($info->get_param('require_login') =~ /^(yes|recent)$/){
      # this page requires that the user has a valid cookie
      $pk->{page_id} = $pk->{login_page};
      $apr->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");
      $pk->message("This page requires a login.");
      $pk->logout;
    }
  }

  # prepare navigation
  if ($info->get_param('use_nav',$pk->{page_id}) eq 'yes') {
    my $nav_page_id = $pk->{page_id};
    my $pkit_nav = [];
    while ($nav_page_id) {
      unshift @$pkit_nav, { name => $info->get_param('nav_title',$nav_page_id),
	       	       page => $nav_page_id
		    };
      $nav_page_id = $info->get_param('parent_id',$nav_page_id);
    }
    $view->param('pkit_nav', $pkit_nav);
  }

  # run the page code!
  my $status_code = $pk->page_code unless $pk->{disable_code};
  return $status_code if $status_code eq REDIRECT;

  Apache::PageKit->call_plugins($pk, 'post_prepare_code_handler');

  # deal with different views
  if(my $pkit_view = $apr->param('pkit_view')){
    $view->param('pkit_view:' . $pkit_view => 1);
  }

  return OK;
}

sub prepare_view {
  my ($pk) = @_;

  return if $pk->{info}->get_param('use_template') eq 'no';

  my $view = $pk->{view};

  # set up page template and run module code
  $view->prepare_page unless $pk->{info}->get_param('use_template') eq 'no';

  $view->prepare_entire_page;
}

sub print_view {
  my ($pk) = @_;

  # $dbh is a DBI object
  my $dbh = $pk->{dbh};

  # $apr is an Apache::Request object
  my $apr = $pk->{apr};

  # $view is an Apache::PageKit::View object
  my $view = $pk->{view};

  # $info is an Apache::PageKit::Info object
  my $info = $pk->{info};

  my $output_ref = $view->output_ref;
  if ($apr->dir_config('SEARCH_ENGINE_HEADERS') == 1 &&
      # set Last-Modified header and content-length fields so that search engines can
      # spider site if page is quasi-static (i.e if doesn't require login)
      $info->get_param('require_login') !~ /^(yes|recent)$/){
    $apr->set_last_modified(time());
    $apr->header_out('Content-Length',length($$output_ref));
  }

  # set expires to now so prevent caching
  #$apr->no_cache(1) if $apr->param('pkit_logout') || $info->get_param('cache') eq 'no';
  # see http://support.microsoft.com/support/kb/articles/Q234/0/67.ASP
  # and http://www.pacificnet.net/~johnr/meta.html
  $apr->header_out('Expires','-1') if $apr->param('pkit_logout') || $info->get_param('browser_cache') eq 'no' || $apr->connection->user;

  return if $pk->{info}->get_param('use_template') eq 'no';

  $apr->content_type('text/html');
  $apr->send_http_header if $apr->is_initial_req;
  return if $apr->header_only;

  $apr->print($$output_ref);

  # save session
  delete $pk->{session};
}

# can be overridden for user home pages
sub get_default_page {
  my $pk = shift;
  my $apr = $pk->{apr};
  if ($apr->dir_config('PKIT_PAGE_DOMAIN') eq 'on' &&
      (my $page_id_by_domain = $pk->{info}->page_id_by_domain((split(':',$pk->{apr}->headers_in->{'Host'}))[0]))){
    return $page_id_by_domain;
  } else {
    return $pk->{default_page};
  }
}

sub new {

  my $class = shift;
  my $r = Apache->request;
  my $self = {@_};

  # set default values
  (exists $self->{fill_in_form} ) || ($self->{fill_in_form} = 1);
  (exists $self->{post_max} ) || ($self->{post_max} = 100000000);
  (exists $self->{login_page} ) || ($self->{login_page} = 'login');
  (exists $self->{default_page} ) || ($self->{default_page} = 'index');
  (exists $self->{recent_login_timeout}) || ($self->{recent_login_timeout} = 3600);
  (exists $self->{module_dispatch_prefix} ) || ($self->{module_dispatch_prefix} = 'MyPageKit::ModuleCode');
  (exists $self->{page_dispatch_prefix} ) || ($self->{page_dispatch_prefix} = 'MyPageKit::PageCode');

  bless $self, $class;

  # get info by virtual host
  my $info = $info_hash{$r->dir_config("PKIT_PAGE_INFO_FILE")} || $self->_child_init($r);

  $self->{apr} = Apache::Request->new($r, POST_MAX => $self->{post_max});
  $self->{info} = $info->associate_pagekit($self);
  $self->{validator} = Apache::PageKit::FormValidator->new($self->{form_validator_input_profile})
    if $self->{form_validator_input_profile};
  $self->{view} = Apache::PageKit::View->new($self);

  # session handling
  if(my $session_handler = $self->{session_handler_class}){
    $self->setup_session;
  }

  return $self;
}

sub page_code {
  my $pk = shift;
  my $page_id = shift || $pk->{page_id};

  # change all the / to ::
  $page_id =~ s!/!::!g;

  # insert a page_ before the method
  $page_id =~ s/^(.*?)([^:]+)$/$1::page_$2/;

  my $page_code_package = $pk->{page_dispatch_prefix} || 
    die "Must specify page_dispatch_prefix in Apache::PageKit->new";

  no strict 'refs';
  my $perl_sub = $page_code_package . $page_id;
  &{$perl_sub}($pk) if defined &{$perl_sub};
}

sub module_code {
  my $pk = shift;
  my $module_id = shift;

  # change all the / to ::
  $module_id =~ s!/!::!g;

  # insert a module_ before the method
  $module_id =~ s/(.*?)([^:]+)$/$1::module_$2/;

  my $module_code_package = $pk->{module_dispatch_prefix} || die "Must specify module_dispatch_prefix in Apache::PageKit->new";

  no strict 'refs';
  my $perl_sub = $module_code_package . $module_id;

  &{$perl_sub}($pk) if defined &{$perl_sub};
}

sub call_plugins {
  my ($class, $object, $handler) = @_;

  no strict 'refs';

  foreach my $class (grep /^Apache\/PageKit\/Plugin\//, keys %INC){
    $class =~ s(/)(::)g;
    $class =~ s(\.pm$)();
    my $perl_sub = $class . "::" . $handler;
    &{$perl_sub}($object) if defined &{$perl_sub};
  }
}

sub login {
  my ($pk, @credentials) = @_;

  my $apr = $pk->{apr};
  my $dbh = $pk->{dbh};
  my $view = $pk->{view};
  my $session = $pk->{session};

  my @credentials;
  while (my $credential = $apr->param("pkit_credential_" . ($#credentials + 1))){
    push @credentials, $credential;
  }

  my $remember = $apr->param('pkit_remember');
  my $done = $apr->param('pkit_done') || $pk->get_default_page;

  my $ses_key = $pk->auth_credential(@credentials);

  $ses_key || return 0;

  # check if user has a saved session_id

  # allow user to view pages with require_login eq 'recent'
  $session->{last_activity} = time();

  # save session
  delete $pk->{session};

  my $cookie = Apache::Cookie->new($apr,
				   -name => 'id',
				   -value => $ses_key,
				   -domain => $apr->dir_config('PKIT_COOKIE_DOMAIN'),
				   -path => "/");
  if ($remember){
    $cookie->expires("+10y");
  }
  $cookie->bake;

  # this is used to check if cookie is set
  if($done =~ /\?/){
    $done .= "&pkit_check_cookie=on";
  } else {
    $done .= "?pkit_check_cookie=on";
  }

  $done =~ s/ /+/g;

  $apr->headers_out->set(Location => "$done");
  return 1;
}

sub authenticate {
  my ($pk) = @_;

  my %cookies = Apache::Cookie->fetch;

  return unless $cookies{'id'};

  my %ticket = $cookies{'id'}->value;

  my $auth_user = $pk->auth_session_key(\%ticket);

  return unless $auth_user;

  $pk->{apr}->connection->user($auth_user);

  $pk->{view}->param(pkit_user => $auth_user);

  return $auth_user;
}

sub logout {
  my ($pk) = @_;

  my $apr = $pk->{apr};

#  my $cookie = Apache::Cookie->new($r);
  my %cookies = Apache::Cookie->fetch;

  return unless defined $cookies{'id'};

  my $tcookie = $cookies{'id'};
#  my %ticket = $tcookie->value;
  $tcookie->value("");
  $tcookie->domain($apr->dir_config('PKIT_COOKIE_DOMAIN'));
  $tcookie->expires('-5y');
  $tcookie->bake;
}

sub message {
  my $pk = shift;
  my $message = shift;
  my $view = $pk->{view};

  my $options = {@_};

  my $array_ref = $view->param('pkit_message') || [];
  push @$array_ref, {message => $message,
		    is_error => $options->{'is_error'}};
  $view->param('pkit_message',$array_ref);
}

# get session_id from cookie
sub setup_session {
  my ($pk) = @_;

  unless(exists $pk->{session_handler_class}){
    $pk->{session} = {};
    return;
  }

  my $apr = $pk->{apr};

  my %cookies = Apache::Cookie->fetch;

  my $session_id;

  if(defined $cookies{'pkit_session_id'}){
    my $scookie = $cookies{'pkit_session_id'};
    $session_id = $scookie->value;
  }

  my $is_new_session;
  my $cookie_domain;

  unless($session_id){
    $cookie_domain = $apr->dir_config('PKIT_COOKIE_DOMAIN');

    # return if user came from a page in the PKIT_COOKIE_DOMAIN - i.e. user should
    # have already had a sessionID, but did not have cookies enabled
    if ($apr->header_in('Referer') =~ m!^(http://)?([^/])*$cookie_domain(/.*)?$!){
      $pk->{session} = {};
      return;
    }
    $is_new_session = 1;
  }

  # set up session handler class
  my %session;

  my $session_handler_class = $pk->{session_handler_class};
  
  eval "require $session_handler_class";
  die $@ if ($@);
  
  eval {
    # avoid errors when old sessions have been deleted from database
    local $Apache::PageKit::Error::in_use = 'no';
    tie %session, $session_handler_class, $session_id, $pk->{session_args};
  };
  if($@){
    # session expired, create new session 
    tie %session, $session_handler_class, undef, $pk->{session_args};
    $cookie_domain = $apr->dir_config('PKIT_COOKIE_DOMAIN');
    $is_new_session = 1;
  }

  $pk->{session} = \%session;

  if($is_new_session){
    # set cookie in users browser
    my $session_id = $session{'_session_id'};
    my $cookie = Apache::Cookie->new($apr,
				     -name => 'pkit_session_id',
				     -value => $session_id,
				     -domain => $cookie_domain,
				     -path => "/");
    $cookie->bake;
  } else {
    # keep recent sessions recent
    # that is sessions time out if user hasn't viewed in a page 
    # in recent_login_timeout seconds
    my $now = time();

    $session{last_activity} = $now
      if $session{last_activity} && 
	$session{last_activity} + $pk->{recent_login_timeout} >= $now;
  }

  # save for logging purposes
  $apr->notes(pkit_session_id => $session_id);

#  $pk->{view}->param('last_activity',$session{last_activity} . " " . $session{_session_id});

  return $session_id;
}

1;

__END__

=head1 NAME

Apache::PageKit - Application framework using mod_perl and HTML::Template

=head1 SYNOPSIS

Perl Module that inherits from Apache::PageKit:

  package MyPageKit;

  use Apache::PageKit;

  use vars qw(@ISA);
  @ISA = qw(Apache::PageKit);

  use Apache::Constants qw(OK REDIRECT DECLINED);

  sub handler {
    $dbh = DBI->connect("DBI:mysql:db","user","passwd");
    my $pk = Apache::MyPageKit->new(
				    page_dispatch_prefix => 'MyPageKit::PageCode',
				    module_dispatch_prefix => 'MyPageKit::ModuleCode',
                                    dbh => $dbh,
				    session_handler_class => 'Apache::Session::MySQL',
				    session_args => {
						     Handle => $dbh,
						     LockHandle => $dbh,
                                                    },
                                   );

    my $status_code = $pk->prepare_page;
    return $status_code unless $status_code eq OK;

    $pk->prepare_view;

    $pk->print_view;

    return $status_code;
  }

  sub auth_credential {
    my ($pk, @credentials) = @_;

    # create a session key from credentials
    # your code here.........

    return $ses_key
  }

  sub auth_session_key {
    my ($pk, $ses_key) = @_;

    # check whether $ses_key is valid, if so return user id in $user_id
    # your code here.........

    return $ok ? $user_id : undef;
  }

In httpd.conf

  PerlSetVar PKIT_ERROR_HANDLER email
  PerlSetVar PKIT_PAGE_INFO_FILE /www/pagekit/page.txt
  PerlSetVar PKIT_PRODUCTION on
  PerlSetVar PKIT_TEMPLATE_ROOT /www/pagekit/template
  PerlSetVar PKIT_COOKIE_DOMAIN .pagekit.org
  PerlRequire /www/pagekit/startup.pl
  SetHandler perl-script
  PerlHandler +MyPageKit
  PerlSetupEnv Off

=head1 DESCRIPTION

PageKit is a set of Perl modules that provides an application framework
based on mod_perl and HTML::Template.  It is based on the
Model/View/Controller approach to design, with complete seperation of
Perl from HTML.  It includes session management, authentication, form
validation, sticky html forms, multiple views/co-branding, modules and includes, and
a simple content management system.

You have to write a module that inherits from Apache::PageKit and provides a handler
for the PerlHandler request phase.  If you wish to support authentication, it must
include the two methods C<auth_credential> and C<auth_session_key>.

For more information, visit http://www.pagekit.org or
http://sourceforge.net/projects/pagekit/

=head1 OBJECTS

Each C<$pk> object contains the following objects:

=over 4

=item $pk->{apr}

An L<Apache::Request> object

=item $pk->{info}

An L<Apache::PageKit::Info> object, which loads and accesses data about the set
of pages making up the the application.

=item $pk->{session}

A reference to a hash tied to L<Apache::Session>.

=item $pk->{validator}

An L<Apache::PageKit::FormValidator> object, a wrapper to HTML::FormValidator, used
for validating HTML forms.

=item $pk->{view}

An L<Apache::PageKit::View> object, which interfaces with the HTML::Template templates.

=back

=head1 Features

=over 4

=item I<Model/View/Controller> approach to design

The Model is the user provided classes, which encapsulate the business logic
behind the web site.

The View is a set of L<HTML::Template> templates.  L<Apache::PageKit::View>
acts as a bridge between the templates and the controller.

The Controller is a subclass of L<Apache::PageKit>, which reads the client request,
accesses the back end, and uses L<Apache::PageKit::View> to fill in the data needed
by the templates.

=item Seperation of Perl from HTML

By using L<HTML::Template>, this application enforces an important divide - 
design and programming.  Designers can edit HTML without having to deal with
any Perl, while programmers can edit the Perl code with having to deal with any HTML.

=item Page based attributes

Many of the attributes of each Page are managed from a tab-delimited file.
This makes it easy to change Pages across the site.  L<Apache::PageKit::Info>
provides a wrapper around this text file.

For example, to protect
a page, all you have to do is change its C<require_login> attribute to I<yes>, instead
of modifying the Perl code or moving the script to a protected directory.

To change a page to a popup, all you have to do is set C<is_popup> to I<yes>, and all
the links to that page across the site will magically become javascript popup links.

=item Automatic Dispatching of URIs

Apache::PageKit translates C<$r-E<gt>uri> into a class and method in the user provided
classes.  In the example in the synopsis,
the URI C</account/update> will map to C<MyPageKit::PageCode::account-E<gt>page_update>.

=item Easy error handling.

Both warnings and fatal errors can be displayed on the screen for easy debugging
in a development environment, or e-mailed to the site adminstrator in a production
environment, as specified in the Apache C<ServerAdmin> configuration directive.

=item Session Management

Provides easy access to a hash tied to L<Apache::Session>.

=item Authentication

Restricts access to pages based on the C<require_login> attribute.  If C<require_login>
is set to I<recent>, then PageKit requires that session is currently active in the last
C<recent_login_timeout> seconds.

=item Form Validation

Uses L<HTML::FormValidator> to provide easy form validation.  Highlights
fields in red that user filled incorrectly by using the C<E<lt>PKIT_ERRORFONT NAME="FIELD_NAME"E<gt> E<lt>E<sol>PKIT_ERRORFONTE<gt>> tag.

=item Sticky HTML Forms

Uses L<HTML::FillInForm> to implement Sticky CGI Forms.

One useful application is after a user submits an HTML form without filling out
a required field.  PageKit will display the HTML form with all the form 
elements containing the submitted info.

=item Multiple Views/Co-branding

Any page can have multiple views, by using a C<pkit_view> request parameter.
One example is Printable pages.  Another
is having the same web site branded differently for different companies.

=item Modules and Includes

PageKit can easily share Perl code and HTML templates across multiple pages using
modules.  To only share HTML, includes can be used.

=item Content Management System

An authorized user can edit the HTML Templates for
views, pages, modules and includes online by simply clicking on
a "edit this (view|page|module|include)" link.

=back

=head1 METHODS

The following methods are available to the user as Apache::PageKit API.

=over 4

=item new

Constructor object.

  $pk = Apache::PageKit->new(
			     page_dispatch_prefix => 'MyPageKit::PageCode',
			     module_dispatch_prefix => 'MyPageKit::ModuleCode',
                             dbh => $dbh,
			     session_handler_class => 'Apache::Session::MySQL',
			     session_args => {
					      Handle => $dbh,
					      LockHandle => $dbh,
                                             },
			    );

Each option is accessible from the object's
hash.  For example C<$dbh> is acessible from C<$pk-E<gt>{dbh}>.

=item prepare_page

This executes all of the back-end business logic need for preparing the page, including
executing the page and module code.

=item prepare_view

This fills in the view template with all of the data from the back-end

=item print_view

Called as a last step to output filled in view template.

=item message

Displays a special message to the user.  The message can displayed using the
C<E<lt>TMPL_LOOP NAME="PKIT_MESSAGE"E<gt> E<lt>E<sol>TMPL_LOOPE<gt>> code.

To add a message,

  $pk->message("Your listing has been deleted.");

To add an error message (highlighted in red), use

  $pk->message("You did not fill out the required fields.",
               is_error => 1);


=item auth_credential

You must define the method yourself in your subclass of C<Apache::PageKit>.

Verify the user-supplied credentials and return a session key.  The
session key can be any string - often you'll use the user ID and
a MD5 hash of a a secret key, user ID, password.

=item auth_session_key

You must define the method yourself in your subclass of C<Apache::PageKit>.

Verify the session key (previously generated by C<auth_credential>)
and return the user ID.
This user ID will be fed to C<$r-E<gt>connection-E<gt>user()>.

=back

=head1 MARKUP TAGS

See the L<HTML::Template> manpage for description of the <TMPL_VAR>,
<TMPL_LOOP>, <TMPL_IF>, and <TMPL_INCLUDE> tags.

=over 4

=item <PKIT_ERRORFONT NAME="FIELD_NAME"> </PKIT_ERRORFONT>

This tag highlights fields in red that L<Apache::PageKit::FormValidator>
reported as being filled in incorrectly.

=item <PKIT_JAVASCRIPT>

This tag includes Javascript code (if necessary) for popup windows.

=item <PKIT_LINK PAGE="143"> </PKIT_LINK>

These tags gets converted to <A HREF="LINK_FOR_PAGE_143"> </A> tags.
Given a page ID, it determines what the link should be.  If
PKIT_PAGE_DOMAIN is turned on, the link may include the domain name
for that page.  If C<is_popup> is I<yes>, then the link will be a
javascript popup.  If C<is_secure> is I<yes>, then the link will use
the C<https://> protocal.

=item <TMPL_VAR NAME="PKIT_ADMIN">

True if user is authenticated and has administration capability.

=item <TMPL_LOOP NAME="PKIT_EDIT"> </TMPL_LOOP>

Links to Content Management System.  This is displayed if
authenticated user has administration capability.

Template should contain code that looks like

  <TMPL_LOOP NAME="PKIT_EDIT">
    <PKIT_LINK PAGE="edit_page?template=<TMPL_VAR NAME="TEMPLATE">&pkit_done=<TMPL_VAR NAME="pkit_done">">(edit template <TMPL_VAR NAME="TEMPLATE">)</PKIT_LINK><<br>
  </TMPL_LOOP>

=item <TMPL_VAR NAME="PKIT_LOGINOUT_LINK">

If user is logged in, provides link to log out.  If user is not logged in,
provides link to log in.

=item <TMPL_LOOP NAME="PKIT_MESSAGE"> </TMPL_LOOP>

Displays messages passed to C<$pk-E<gt>message> method.

Template should contain something that looks like

  <TMPL_LOOP NAME="PKIT_MESSAGE">
     <TMPL_IF NAME="IS_ERROR"><font color="#ff0000"></TMPL_IF>
     <TMPL_VAR NAME="MESSAGE">
     <TMPL_IF NAME="IS_ERROR"></font></TMPL_IF>
     <p>
  </TMPL_LOOP>

This code will show error messages in red.

=item <TMPL_VAR NAME="PKIT_MODULE:module_id">

Calls the module code and includes the module template for the module I<module_id>.

=item <TMPL_LOOP NAME="PKIT_NAV"> </TMPL_LOOP>

Displays navigation for pages that have C<use_nav> set to I<yes>.

Template should contain code that looks like

  <TMPL_LOOP NAME="PKIT_NAV">
    <TMPL_UNLESS NAME="__LAST__"><PKIT_LINK PAGE="<tmpl_var name="page">"></TMPL_UNLESS><TMPL_VAR NAME="NAME"><TMPL_UNLESS NAME="__LAST__"></PKIT_LINK></TMPL_UNLESS>
    <TMPL_UNLESS NAME="__LAST__"> &gt; </TMPL_UNLESS>
  </TMPL_LOOP>

=item <TMPL_VAR NAME="PKIT_PAGE">

Includes the Page template inside a View template.

=item <TMPL_VAR NAME="PKIT_SELFURL">

The URL of the current page, including CGI parameters.
Appends a '&' or '?' at the end to allow additionial parameters.

=item <TMPL_VAR NAME="PKIT_USER">

user_id of authenticated user, equal to
C<$r-E<gt>connection-E<gt>user>, unless overridden.

=item <TMPL_IF NAME="PKIT_VIEW:I<view>"> </TMPL_IF>

Set to true if C<pkit_view> request parameter equals I<view>.

=back

=head1 OPTIONS

=head2 Constructor Arguments

These sessions are global in the sense that they apply over all pages and servers.

=over 4

=item cookies_not_set_page

This is the page that gets displayed if the user attempts to log in,
but their cookies are not enabled.  Defaults to C<login_page>.

=item default_page

Default page user gets when no page is specified.  Defaults to I<index>.

=item fill_in_form

When set to 1, automatically fills in HTML forms with values from the C<$apr> 
(L<Apache::Request>) object.  Defaults to 1.

=item login_page

Page that gets displayed when user attempts to log in.  Defaults to I<login>.

=item module_dispatch_prefix

This prefixes the class that the contains the module code.  Defaults to MyPageKit::ModuleCode.

=item not_found_page

Error page when page cannot be found.  Defaults to C<default_page>.

=item page_dispatch_prefix

This prefixes the class that the contains the page code.  Defaults to MyPageKit::PageCode.

=item post_max

Maximum size of file uploads.  Defaults to 100000000 (100 MB).

=item recent_login_timeout

Seconds that user's session has to be inactive before a user is asked
to verify a password on pages with the C<require_login> attribute
set to I<recent>.  Defaults to 3600 (1 hour).

=item session_args

Reference to an hash containing options for the C<session_handler_class>.

=item session_handler_class

The subclass of L<Apache::Session> that should be used for
session handler.

=item uri_prefix

Prefix of URI that should be trimmed before dispatching to the Page code.

=item verify_page

Verify password form.  Defaults to C<login_page>.

=item view_cache

If set to I<normal>, enables C<cache> option of L<HTML::Template> for the View template.

If set to I<shared>, enables C<shared_cache> option of L<HTML::Template>.

=back

=head2 Apache Configuration

These options are global over all pages, but are local to each server configuration
(production, staging, development).

=over 4

=item PKIT_COOKIE_DOMAIN

  PKIT_COOKIE_DOMAIN .pagekit.org

Domain for that cookies are issued.  Note that you must have
at least two periods in the cookie domain.

=item PKIT_ERROR_HANDLER

  PKIT_ERROR_HANDLER (email|display|none)

Specifies the type of error handling.  I<email> e-mails the
server administrator, I<display> displays the error on the web page.

Default is I<none>.

=item PKIT_FILES_MATCH

  PKIT_FILES_MATCH \.html?$

Declines requests that match value.

=item PKIT_PAGE_DOMAIN

  PKIT_PAGE_DOMAIN (on|off)

If on, multiple domains are used for the site.  Domains
can be used to map to pages.  Default is off.

=item PKIT_PAGE_INFO_FILE

  PKIT_PAGE_INFO_FILE /www/site/page.txt

Tab delimited file containing page attributes.

=item PKIT_PRODUCTION

  PKIT_PRODUCTION (on|off)

Set to on, if in production environment.  If set to off,
checks for new C<PKIT_PAGE_INFO_FILE> for each request.

Default is off.

=item PKIT_SEARCH_ENGINE_HEADERS

  PKIT_SEARCH_ENGINE_HEADERS (on|off)

If set to on, sends I<Content-Length> and I<Last-Modified> headers on pages that
don't require a login.  Many search engines require that these headers be set
in order to index a page.

Default is off.

=item PKIT_SUBDOMAIN

  PKIT_SUBDOMAIN staging

This specifies the subdomain under the domain that this particular
server is running.  Only needs to be set if C<PKIT_PAGE_DOMAIN> is on.

Used in development environments where the hostname is different
from the production environment.

=item PKIT_TEMPLATE_ROOT

  PKIT_TEMPLATE_ROOT /www/site/template

Directory containing L<HTML::Template> files.  Defaults to the Apache
C<DocumentRoot> configuration directive.

=back

=head2 Page Attributes

These options are local to each page on the site, but are global across each server.

=over 4

=item page_id (required)

Page ID for this page.

=item view (required)

View template that is used to display page.

=item browser_cache

If set to I<no>, sends an Expires = -1 header to disable client-side
caching on the browser.

=item domain

The domain name that is associated with the page.

=item error_page

If a submitted form includes invalid data, then this is the page 
that is displayed.

=item error_page_run_code

If set to I<yes>, then page_code on error_page is run.  Defaults to I<no>.

=item is_popup

If set to I<yes>, links to this page popup a window using javascript.

=item is_secure

If set to I<yes>, links to this page will begin with C<https://>.

=item is_topdomain

If set to I<yes>, page will be the default page for the domain specified
in the C<domain> field.

=item nav_title

Title used in navigation bar - used in C<E<lt>TMPL_LOOP NAME="PKIT_NAV"E<gt> E<lt>E<sol>TMPL_LOOPE<gt>> tag.

=item new_credential

Should be set to I<yes> for pages that process credentials and update the
database, such as pages that process new registration and edit account forms.

If set to I<yes>, then it reissues the cookie that contains the credentials and
authenticates the user.

=item page_id_match

Value should be a regular expression.
Servers requests whose URL (after the host name) match the regular expression.
For example, C<^member\E<sol>\d*$> matches http://yourdomain.tld/member/4444.

=item parent_id

Parent page id - used for navigation bar.

=item popup_width

Width of popup window.  Used when C<is_popup> is set to I<yes>.

=item popup_height

Height of popup window.  Used when C<is_popup> is set to I<yes>.

=item require_login

If set to I<yes>, page requires a login.  If set to I<recent>, page
requires a login and that the user has been active in the last
C<recent_login_timeout> seconds.  Default is I<no>.

=item template_cache

If set to I<normal>, enables C<cache> option of L<HTML::Template> for the Page and Module templates.

If set to I<shared>, enables C<shared_cache> option of L<HTML::Template>.

=item use_nav

If set to I<yes>, creates navigation bar in location specified by
C<E<lt>TMPL_LOOP NAME="PKIT_NAV"E<gt> E<lt>E<sol>TMPL_LOOPE<gt>> in the template.

=item use_template

If set to I<yes>, uses HTML::Template files.  If set to I<no> page code
is responsible for sending output.  Default is I<yes>.

=back

=head1 REQUEST PARAMETERS

These are parameters that are specified in B<GET> requests and B<POST> requests where
I<Content-type> is one of I<application/x-www-form-urlencoded> or I<multipart/form-data>.

=over 4

=item pkit_credential_#

Login data, typically userid/login/email (pkit_credential_0) and
password (pkit_credential_1).

=item pkit_done

The page to return to after the user has finished logging in or creating a new account.

=item pkit_login_page

This parameter is used to specify the page that user attempted to login from.
If the login fails, this page is redisplayed.

=item pkit_remember

If set to true upon login, will save user's cookie so that they are still logged
in next time they restart their browser.

=item pkit_view

Used to implement multiple views/co-branding.  For example, if set to I<print>,
will search for templates ending with C<.print.tmpl> before using templates ending
with C<.tmpl>, and sets the C<pkit_view:print> parameter in the view to true.

=back

=head1 SEE ALSO

L<Apache::PageKit::Error>,
L<Apache::PageKit::FormValidator>, L<Apache::PageKit::Info>, L<Apache::PageKit::View>,
L<Apache::Request>, L<HTML::FillInForm>, L<HTML::Template>,
L<HTML::FormValidator>

=head1 VERSION

This document describes Apache::PageKit module version 0.01

=head1 NOTES

Requires mod_perl, HTML::FillInForm, HTML::FormValidator, and HTML::Template.

I wrote these modules because I needed an application framework that was based
on mod_perl and seperated HTML from Perl.  HTML::Embperl, Apache::ASP 
and HTML::Mason are frameworks that work with mod_perl, but embed Perl code
in HTML.  The development was inspired in part by Webmacro, which
is an open-source Java servlet framework that seperates Code from HTML.

The goal is of this module is to develop a framework that provides most of the
functionality that is common across dynamic web sites, including session management,
authorization, form validation, component design, error handling, and content management.

=head1 BUGS

This framework is in alpha stage.  The interface may change in later
releases.

Please submit any bug reports, comments, or suggestions to
tjmather@thoughtstore.com, or join the Apache::PageKit
mailing list at http://lists.sourceforge.net/mailman/listinfo/pagekit-users

=head1 TODO

Associate sessions with authenticated user ID.

Use path_info for the url to pass along session IDs when cookies are disabled.

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

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license
