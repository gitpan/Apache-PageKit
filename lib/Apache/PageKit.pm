package Apache::PageKit;

# $Id: PageKit.pm,v 1.13 2000/12/23 07:10:38 tjmather Exp $

# CPAN Modules required for pagekit
use Apache::URI ();
use Apache::Cookie ();
use Apache::Request ();
use Apache::Util ();
use HTML::FillInForm ();
use HTML::FormValidator ();
use HTML::Parser ();
use HTML::Template ();
use Mail::Mailer ();
use XML::Parser ();

# PageKit modules
use Apache::PageKit::View ();
use Apache::PageKit::Model ();
use Apache::PageKit::Session ();
use Apache::PageKit::Content ();
use Apache::PageKit::Config ();

use strict;

use Apache::Constants qw(OK REDIRECT DECLINED);

use vars qw($VERSION %info_hash);
$VERSION = '0.9';

BEGIN {
  # include user defined classes (Model) in perl search path
  my $s = Apache->server;
  my $pkit_root = $s->dir_config('PKIT_ROOT');
  unshift(@INC,"$pkit_root/Model");
}

# called when Apache::PageKit is first loaded (should be at Apache startup)
&startup;

sub startup {
  my $s = Apache->server;
  my $pkit_root = $s->dir_config('PKIT_ROOT');
  my $config_dir = $pkit_root . '/Config';
  my $config = Apache::PageKit::Config->new(config_dir => $config_dir);
  $config->parse_xml;
  my $page_dispatch_prefix = $config->get_global_attr('page_dispatch_prefix');

  # clean and pre-parse templates
  Apache::PageKit::View->preparse_templates($pkit_root . '/View',
			$config->get_global_attr('html_clean_level'));

  # Alias /pkit_edit/ urls to be dispatched to Apache::PageKit::Edit;
# this should be enabled for v0.91 (with Apache::PageKit::Edit)
#  {
#    no strict 'refs';
#    *{$page_dispatch_prefix . "::pkit_edit::"} = \%Apache::PageKit::Edit;
#  }

  my $content_dir = $pkit_root . '/Content';
  my $default_lang = $config->get_global_attr('default_lang') || 'en';
  my $content = Apache::PageKit::Content->new(content_dir => $content_dir,
					default_lang => $default_lang);
  # cache content in files using Storable
  $content->parse_all;
}

sub _params_as_string {
  my ($apr) = @_;
  my $query_string = join ('&', map {$_ . "=" . $apr->param($_)} $apr->param);

  # make available for future use (such as logging stage)
  $apr->notes('query_string', $query_string);

  return join ('&', map { Apache::Util::escape_uri("$_") ."=" . Apache::Util::escape_uri($apr->param($_) || "")} grep !/^(pkit_logout|pkit_view)$/, $apr->param);
}

sub prepare_page {
  my $pk = shift;

  # $apr is an Apache::Request object
  my $apr = $pk->{apr};

  # $view is an Apache::PageKit::View object
  my $view = $pk->{view};

  # $config is an Apache::PageKit::Config object
  my $config = $pk->{config};

  # $content is an Apache::PageKit::Content object
  my $content = $pk->{content};

  # $model is an Apache::PageKit::Model object
  my $model = $pk->{model};

  # decline to serve images, etc
#  return DECLINED if $apr->content_type && $apr->content_type !~ m|^text/|io;

  my $uri = $apr->uri;

  # decline files_match
  if (my $files_match = $config->get_server_attr('files_match')){
    return DECLINED if $uri =~ m/$files_match/;
  }

  if(my $uri_prefix = $config->get_global_attr('uri_prefix')){
    $uri =~ s(^/$uri_prefix)(/);
  }

  $pk->{page_id} = $uri;

  # get rid of leading forward slash
  $pk->{page_id} =~ s(^/+)();

  # add index for pageid with trailing slash "/"
  $pk->{page_id} =~ s!(.+)/$!$1/index!;

  # get default page if there is no page specified in url
  if($pk->{page_id} eq ''){
    $pk->{page_id} = $config->get_global_attr('default_page');
  }

  # redirect "not found" pages
  unless ($pk->page_exists($pk->{page_id})){
    $pk->{page_id} = $config->page_id_match($pk->{page_id})
      || $config->get_global_attr('not_found_page')
      || $config->get_global_attr('default_page');
  }

  # new registration and edit profile requires special handling
  # the page code needs to be called _before_ the login code runs
  if($config->get_page_attr($pk->{page_id},'new_credential') eq 'yes'){
    $pk->authenticate; 
    $pk->page_code unless $pk->{disable_code};
  }

  my $uri_with_query = $uri;
  my $pkit_selfurl;
  my $query_string = _params_as_string($apr);
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
  my $pkit_done = $apr->param('pkit_done') || 'http://' . $host . $uri_with_query;
  $pkit_done =~ s/"/\%22/g;
  $pkit_done =~ s/&/\%26/g;
  $pkit_done =~ s/\?/\%3F/g;
  $view->param("pkit_done",$pkit_done);

  my $auth_user;

  my @credentials;
  while (my $credential = $apr->param("pkit_credential_" . ($#credentials + 1))){
    push @credentials, $credential;
  }

  # if pkit_crendential_0 field is present, user is attempting to log in
  if(defined $apr->param('pkit_credential_0')){
    if ($pk->login(@credentials)){
      # if login is sucessful, redirect to (re)set cookie
      return REDIRECT;
    } else {
      # else return to login form
#      my $referer = $apr->header_in('Referer');
#      $referer =~ s(http://[^/]*/([^?]*).*?)($1);
      $pk->{page_id} = $apr->param('pkit_login_page') || $config->get_global_attr('login_page');
    }
  } elsif($apr->param('pkit_logout')){
    $pk->logout;
    $apr->param('pkit_check_cookie','');
    # goto home page when user logouts (if from page that requires login) 
    my $add_message = "";
    unless ($config->get_page_attr($pk->{page_id},'require_login') eq 'no'){
      $pk->{page_id} = $config->get_global_attr('login_page');
      $add_message = "You can log back in again below:";
    }
    $pk->message("You have sucessfully logged out.  $add_message");
  } else {
    $auth_user = $pk->authenticate;
  }

  if($auth_user){
    # user is logged in, put "log out" link pkit_loginout_link variable

    $pk->message("You have sucessfully logged in.")
      if($apr->param('pkit_check_cookie') eq 'on');

    my $link = $uri_with_query;

    $link =~ s/ /+/g;
    if ($link =~ /\?/){
      $link .= '&pkit_logout=yes';
    } else {
      $link .= '?pkit_logout=yes';
    }
    $view->param('pkit_loginout_link', $link);

    if ($config->get_page_attr($pk->{page_id},'require_login') eq 'recent' &&
	$pk->{session}->{last_activity} + $config->get_global_attr('recent_login_timeout') < time()){
      # user is logged in, but has not been active recently

      # display verify password form
      $pk->{page_id} = $config->get_global_attr('verify_page') ||
			$config->get_global_attr('login_page');
      # pkit_done parameter is used to return user to page that they originally requested
      # after login is finished
      $apr->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");
    }
  } else {
    # user is not logged in, display "log in" link
    $view->param('pkit_loginout_link', $config->get_global_attr('login_page') . "?pkit_done=$pkit_done");

    # check if cookies should be set
    if($apr->param('pkit_check_cookie') eq 'on'){
      # cookies should be set but aren't.
      if($config->get_global_attr('cookies_not_set_page')){
	# display "cookies are not set" error page.
	$pk->{page_id} = $config->get_global_attr('cookies_not_set_page');
      } else {
	# display login page with error message
	$pk->{page_id} = $config->get_global_attr('login_page');
	$pk->message("Cookies must be enabled in your browser.",
		    is_error => 1);
      }
    }

    if($config->get_page_attr($pk->{page_id},'require_login') =~ /^(yes|recent)$/){
      # this page requires that the user has a valid cookie
      $pk->{page_id} = $config->get_global_attr('login_page');
      $apr->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");
      $pk->message("This page requires a login.");
      $pk->logout;
    }
  }

  # run the page code!
  my $status_code = $pk->page_code unless $pk->{disable_code};
  $status_code ||= $pk->{status_code};
  return $status_code if $status_code eq 'REDIRECT';

  # prepare navigation
  if ($config->get_page_attr($pk->{page_id},'use_bread_crumb') eq 'yes') {
    my $nav_page_id = $pk->{page_id};
    my $pkit_cookie_crumb = [];
    while ($nav_page_id) {
      unshift @$pkit_cookie_crumb, { pkit_name => $content->get_param($nav_page_id,'pkit_nav_title'),
			    pkit_page => $nav_page_id
			  };
      $nav_page_id = $config->get_page_attr($nav_page_id,'parent_id');
    }
    $view->param('pkit_cookie_crumb', $pkit_cookie_crumb);
  }

  # deal with different views
  if(my $pkit_view = $apr->param('pkit_view')){
    $view->param('pkit_view:' . $pkit_view => 1);
  }

  return OK;
}

sub prepare_view {
  my ($pk) = @_;

  return if $pk->{config}->get_page_attr($pk->{page_id},'use_template') eq 'no';

  # set up page template and run component code
  $pk->{view}->prepare_output;
}

sub print_view {
  my ($pk) = @_;

  # $apr is an Apache::Request object
  my $apr = $pk->{apr};

  # $view is an Apache::PageKit::View object
  my $view = $pk->{view};

  # $config is an Apache::PageKit::Config object
  my $config = $pk->{config};

  my $output_ref = $view->output_ref;
  if ($config->get_server_attr('search_engine_headers') eq 'yes' &&
      $config->get_page_attr($pk->{page_id}, 'require_login') !~ /^(yes|recent)$/){
    # set Last-Modified header and content-length fields so that search engines can
    # spider site if page is quasi-static (i.e if doesn't require login)
    # META: not sure if this works properly
    $apr->set_last_modified(time());
    $apr->header_out('Content-Length',length($$output_ref));
  }

  # set expires to now so prevent caching
  #$apr->no_cache(1) if $apr->param('pkit_logout') || $config->get_page_attr($pk->{page_id},'template_cache') eq 'no';
  # see http://support.microsoft.com/support/kb/articles/Q234/0/67.ASP
  # and http://www.pacificnet.net/~johnr/meta.html
  $apr->header_out('Expires','-1') if $apr->param('pkit_logout') || $config->get_page_attr($pk->{page_id},'browser_cache') eq 'no' || $apr->connection->user;

  return if $config->get_page_attr($pk->{page_id},'use_template') eq 'no';

  $apr->content_type('text/html');
  $apr->send_http_header if $apr->is_initial_req;
  return if $apr->header_only;

  $apr->print($$output_ref);

  # save session
  delete $pk->{session};
}

sub new {

  my $class = shift;
  my $r = Apache->request;
  my $self = {@_};

  bless $self, $class;

  # set up contained objects
  my $pkit_root = $r->dir_config('PKIT_ROOT');
  my $config_dir = $pkit_root . '/Config';
  my $content_dir = $pkit_root . '/Content';
  my $server = $r->dir_config('PKIT_SERVER');
  $self->{config} = Apache::PageKit::Config->new(config_dir => $config_dir,
						server => $server);
  $self->{apr} = Apache::Request->new($r, POST_MAX => $self->{config}->get_global_attr('post_max'));
  $self->{model} = Apache::PageKit::Model->new($self);

  # session handling
  if($self->{session_lock_class} && $self->{session_store_class}){
    $self->setup_session;
  }

  $self->{view} = Apache::PageKit::View->new($self);

  my $default_lang = $self->{config}->get_global_attr('default_lang') || 'en';
  $self->{content} = Apache::PageKit::Content->new(content_dir => $content_dir,
						default_lang => $default_lang,
						lang_arrayref => $self->{view}->{lang},
						reload => $self->{config}->get_server_attr('reload'));

  return $self;
}

sub page_sub {
  my $pk = shift;
  my $page_id = shift || $pk->{page_id};

  # change all the / to ::
  $page_id =~ s!/!::!g;

  # insert a page_ before the method
  $page_id =~ s/^(.*?)([^:]+)$/$1::page_$2/;

  my $page_code_package = $pk->{config}->get_global_attr('page_dispatch_prefix');

  my $perl_sub = $page_code_package . $page_id;
  return $perl_sub if defined &{$perl_sub};
}

sub page_code {
  my $pk = shift;
  my $perl_sub = $pk->page_sub;
  no strict 'refs';
  return &{$perl_sub}($pk) if $perl_sub;
}

sub component_code {
  my $pk = shift;
  my $component_id = shift;

  # change all the / to ::
  $component_id =~ s!/!::!g;

  # insert a module_ before the method
  $component_id =~ s/(.*?)([^:]+)$/$1::component_$2/;

  my $component_code_package = $pk->{config}->get_global_attr('component_dispatch_prefix');

  no strict 'refs';
  my $perl_sub = $component_code_package . $component_id;

  &{$perl_sub}($pk) if defined &{$perl_sub};
}

sub login {
  my ($pk, @credentials) = @_;

  my $apr = $pk->{apr};
  my $view = $pk->{view};
  my $config = $pk->{config};
  my $session = $pk->{session};

  my $remember = $apr->param('pkit_remember');
  my $done = $apr->param('pkit_done') || $config->get_global_attr('default_page');

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
				   -domain => $config->get_server_attr('cookie_domain'),
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

#  my $cookie = Apache::Cookie->new($r);
  my %cookies = Apache::Cookie->fetch;

  return unless defined $cookies{'id'};

  my $tcookie = $cookies{'id'};
#  my %ticket = $tcookie->value;
  $tcookie->value("");
  $tcookie->domain($pk->{config}->get_server_attr('cookie_domain'));
  $tcookie->expires('-5y');
  $tcookie->bake;
}

sub message {
  my $pk = shift;
  my $message = shift;
  my $view = $pk->{view};

  my $options = {@_};

  my $array_ref = $view->param('pkit_message') || [];
  push @$array_ref, {pkit_message => $message,
		    pkit_is_error => $options->{'is_error'}};
  $view->param('pkit_message',$array_ref);
}

# redirect to another page, should be called from pagecode
sub redirect {
  my ($pk, $new_uri) = @_;

  $pk->{apr}->headers_out->set(Location => "$new_uri");
  $pk->{status_code} = REDIRECT;
}

# continue onto another page without doing a httpd redirect, should be called
# from pagecode
sub continue {
  my ($pk, $new_page_id, $no_code) = @_;

  $pk->{page_id} = $new_page_id;
  if ($no_code){
    $pk->{disable_code} = 1;
  } else {
    $pk->page_code;
  }
}

# get session_id from cookie
sub setup_session {
  my ($pk) = @_;

  unless(exists $pk->{session_lock_class} && exists $pk->{session_store_class}){
    $pk->{session} = {};
    return;
  }

  my $apr = $pk->{apr};
  my $config = $pk->{config};

  my %cookies = Apache::Cookie->fetch;

  my $session_id;

  if(defined $cookies{'pkit_session_id'}){
    my $scookie = $cookies{'pkit_session_id'};
    $session_id = $scookie->value;
  }

  my $is_new_session;
  my $cookie_domain;

  $is_new_session = 1 unless $session_id;

  # set up session handler class
  my %session;

  my $session_lock_class = $pk->{session_lock_class};
  my $session_store_class = $pk->{session_store_class};

  {
    local $Apache::PageKit::Error::in_use = 'no';
    tie %session, 'Apache::PageKit::Session', $session_id,
    {
     Lock => $session_lock_class,
     Store => $session_store_class,
     Generate => 'MD5',
     Serialize => 'Storable',
     create_unknown => 1,
     %{$pk->{session_args}}
    };
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
	$session{last_activity} + $config->get_global_attr('recent_login_timeout') >= $now;
  }

  # save for logging purposes
  $apr->notes(pkit_session_id => $session_id);

  return $session_id;
}

# check to see if page has either template or perl code associated with it
sub page_exists{
  my ($pk, $page_id) = @_;

  # check to see if template file exists
  return 1 if $pk->{view}->template_file_exists($page_id);

  # check to see if perl subroutine for page exists
  return 1 if $pk->page_sub;
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
    my $pk = __PACKAGE__->new(
			      dbh => $dbh,
			      session_lock_class => 'MySQL',
			      session_store_class => 'MySQL',
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

    # create a session key from @credentials
    # your code here.........

    return $ses_key;
  }

  sub auth_session_key {
    my ($pk, $ses_key) = @_;

    # check whether $ses_key is valid, if so return user id in $user_id
    # your code here.........

    return $ok ? $user_id : undef;
  }

In httpd.conf

  SetHandler perl-script
  PerlSetVar PKIT_ROOT /path/to/pagekit/files

  # this comes before PerlHandler so that PKIT_ROOT/Module gets added to @INC
  PerlModule Apache::PageKit 
  PerlHandler +MyPageKit

=head1 DESCRIPTION

PageKit is an mod_perl based application framework that uses HTML::Template and
XML to separate code, design, and content. Includes session management,
authentication, form validation, co-branding, and a content management system.

Its goal is to solve all the common problems of web programming, and to make
the creation and maintenance of dynamic web sites fast, easy and enjoyable.

You have to write a module that inherits from Apache::PageKit and provides a handler
for the PerlHandler request phase.  If you wish to support authentication, it must
include the two methods C<auth_credential> and C<auth_session_key>.

For more information, visit http://www.pagekit.org/ or
http://sourceforge.net/projects/pagekit/

=head1 OBJECTS

Each C<$pk> object contains the following objects:

=over 4

=item $pk->{apr}

An L<Apache::Request> object.  This gets the request parameters and can also
be used to set the default values in HTML form when C<fill_in_form> is set.

=item $pk->{config}

An L<Apache::PageKit::Config> object, which loads and accesses 
global, server and page attributes.

=item $pk->{content}

An L<Apache::PageKit::Content> object, which accesses the content
stored in the XML files.

=item $pk->{model}

An L<Apache::PageKit::Model> object, currently used
for validating HTML forms.

=item $pk->{session}

A reference to a hash tied to L<Apache::PageKit::Session>.

=item $pk->{view}

An L<Apache::PageKit::View> object, which interfaces with the HTML::Template templates.

=back

=head1 Features

=over 4

=item I<Model/View/Content/Controller> approach to design

The Model is the user provided classes, which encapsulate the business logic
behind the web site.

The View is a set of L<HTML::Template> templates.  L<Apache::PageKit::View>
acts as a bridge between the templates and the controller.

The Content is stored in XML files in the Content/xml directory.
You may also store the content in the HTML::Template templates, if you don't
need to seperate the View from the Content.

The Controller is a subclass of L<Apache::PageKit>, which reads the client request,
accesses the back end, and uses L<Apache::PageKit::View> to fill in the data needed
by the templates.

=item Seperation of Perl from HTML

By using L<HTML::Template>, this application enforces an important divide - 
design and programming.  Designers can edit HTML without having to deal with
any Perl, while programmers can edit the Perl code with having to deal with any HTML.

=item Seperation of Content from Design with XML

By using the C<E<lt>CONTENT_VARE<gt>> and C<E<lt>CONTENT_LOOPE<gt>> elements,
you can autofill the corresponding C<E<lt>CONTENT_VARE<gt>>
and C<E<lt>CONTENT_LOOPE<gt>> tags in the template.

This is an easy way of using XML with HTML::Template that doesn't require
the use of stylesheets.

=item Page based attributes

The attributes of each Page are stored in the Config/Config.xml file.
This makes it easy to change Pages across the site.  L<Apache::PageKit::Config>
provides a wrapper around this XML file.

For example, to require a login for
a page, all you have to do is change the  C<require_login> attribute of the
XML C<E<lt>PAGEE<gt>> tag to I<yes>, instead
of modifying the Perl code or moving the script to a protected directory.

=item Automatic Dispatching of URIs

Apache::PageKit translates C<$r-E<gt>uri> into a class and method in the user provided
classes.  In the example in the synopsis,
the URI C</account/update> will map to C<MyPageKit::PageCode::account-E<gt>page_update>.

=item Easy error handling.

Both warnings and fatal errors can be displayed on the screen for easy debugging
in a development environment, or e-mailed to the site adminstrator in a production
environment, as specified in the Apache C<ServerAdmin> configuration directive.

You have to require L<Apache::PageKit::Error> to turn on error handling.

=item Session Management

Provides easy access to a hash tied to L<Apache::PageKit::Session>.

=item Authentication

Restricts access to pages based on the C<require_login> attribute.  If C<require_login>
is set to I<recent>, then PageKit requires that session is currently active in the last
C<recent_login_timeout> seconds.

=item Form Validation

Uses L<HTML::FormValidator> to provide easy form validation.  Highlights
fields in red that user filled incorrectly by using the
C<E<lt>PKIT_ERRORFONT NAME="FIELD_NAME"E<gt> E<lt>/PKIT_ERRORFONTE<gt>> tag.
To use, pass an input profile to the validate method of L<Apache::PageKit::Model> from your perl code option.

=item Sticky HTML Forms

Uses L<HTML::FillInForm> to implement Sticky CGI Forms.

One useful application is after a user submits an HTML form without filling out
a required field.  PageKit will display the HTML form with all the form 
elements containing the submitted info.

=item Multiple Views/Co-branding

Any page can have multiple views, by using the C<pkit_view> request parameter.
One example is Printable pages.  Another
is having the same web site branded differently for different companies.

=item Components

PageKit can easily share HTML templates across multiple pages using
components.  In addition, you may specify Perl code that gets called every
time a component is used by adding a component_I<component_id> method to
the Perl module specified by C<component_dispatch_prefix>.

=item Language Localization

You may specify language properties by the C<xml:lang> attribute
for <CONTENT_VAR> and <CONTENT_LOOP> tags in the XML content files.

The language displayed is based on the
user's preference, defaulting to the browser settings.

=back

=head1 METHODS

The following methods are available to the user as Apache::PageKit API.

=over 4

=item new

Constructor object.

  $pk = __PACKAGE__->new(
			 dbh => $dbh,
			 session_lock_manager => 'MySQL',
			 session_object_store => 'MySQL',
			 session_args => {
					  Handle => $dbh,
					  LockHandle => $dbh,
					 },
			);

Each option is accessible from the object's
hash.  For example C<$dbh> is acessible from C<$pk-E<gt>{dbh}>.

=item prepare_page

This executes all of the back-end business logic need for preparing the page, including
executing the page and component code.

=item prepare_view

This fills in the view template with all of the data from the back-end

=item print_view

Called as a last step to output filled in view template.

=item message

Displays a special message to the user.  The message can displayed using the
C<E<lt>PKIT_LOOP NAME="MESSAGE"E<gt> E<lt>/PKIT_LOOPE<gt>> code.

To add a message,

  $pk->message("Your listing has been deleted.");

To add an error message (typically highlighted in red), use

  $pk->message("You did not fill out the required fields.",
               is_error => 1);

=item redirect

Redirects to the specified URL.  Should be called from the back-end code specified by C<page_dispatch_prefix>.

  package MyPageKit::PageCode;

  sub page_id {
    my $pk = shift;

    $pk->redirect("http://yourdomain.com/new_page");
  }

=item continue

Continues onto another PageKit page.  Should be called from the back-end code
as specified by C<page_dispatch_prefix>.

  $pk->continue($new_page_id, $no_code);

C<$page_id> specifies the new page.  If C<$no_code>
is set to 1, then method doesn't execute
the associated page code.  C<$no_code> defaults to 0.

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

Most tags get "compiled" into <TMPL_VAR>, <TMPL_LOOP>, <TMPL_IF>,
<TMPL_UNLESS>, and <TMPL_ELSE> tags.
See the L<HTML::Template> manpage for description of these tags.

=over 4

=item <PKIT_COMPONENT NAME="component_id">

Calls the component code (if applicable) and includes the template for
the component I<component_id>.

=item <PKIT_ERRORFONT NAME="FIELD_NAME"> </PKIT_ERRORFONT>

This tag highlights fields in red that L<Apache::PageKit::Model>
reported as being filled in incorrectly.

=item <PKIT_LOOP NAME="BREAD_CRUMB"> </PKIT_LOOP>

Displays a bread crumb trail (a Yahoo-like horizontal navigation that 
looks like Top > Category > Sub Category > Current Page )
for pages that have C<bread_crumb> set to I<yes>.

Template should contain code that looks like

  <PKIT_LOOP NAME="BREAD_CRUMB">
    <PKIT_UNLESS NAME="__LAST__"><a href="/<tmpl_var name="page">"></PKIT_UNLESS><PKIT_VAR NAME="NAME"><PKIT_UNLESS NAME="__LAST__"></a></PKIT_UNLESS>
    <PKIT_UNLESS NAME="__LAST__"> &gt; </PKIT_UNLESS>
  </PKIT_LOOP>

=item <PKIT_IF NAME="INTERNET_EXPLORER"> </PKIT_IF>

Set to 1 if User-Agent is a Microsoft Internet Explorer browser.

=item <PKIT_VAR NAME="LOGINOUT_LINK">

If user is logged in, provides link to log out.  If user is not logged in,
provides link to log in.

=item <PKIT_LOOP NAME="MESSAGE"> </PKIT_LOOP>

Displays messages passed to C<$pk-E<gt>message> method.

Template should contain something that looks like

  <PKIT_LOOP NAME="MESSAGE">
     <PKIT_IF NAME="IS_ERROR"><font color="#ff0000"></PKIT_IF>
     <PKIT_VAR NAME="MESSAGE">
     <PKIT_IF NAME="IS_ERROR"></font></PKIT_IF>
     <p>
  </PKIT_LOOP>

This code will display error message seperated by the HTML C<E<lt>pE<gt>> tag,
highlighting error messages in red.

=item <PKIT_IF NAME="NETSCAPE"> </PKIT_IF>

Set to 1 if User-Agent is a Netscape browser.

=item <PKIT_VAR NAME="SELFURL">

The URL of the current page, including CGI parameters.
Appends a '&' or '?' at the end to allow additionial parameters.

=item <PKIT_VAR NAME="USER">

user_id of authenticated user, equal to
C<$r-E<gt>connection-E<gt>user>, unless overridden.

=item <PKIT_IF NAME="VIEW:I<view>"> </PKIT_IF>

Set to true if C<pkit_view> request parameter equals I<view>.

=back

=head1 OPTIONS

=head2 Constructor Arguments

These arguments are global in the sense that they apply over all pages and servers.

=over 4

=item session_args

Reference to an hash containing options for the C<session_lock_class> and
C<session_store_class>.

=item session_lock_class

The lock manager class that should be used for L<Apache::PageKit::Session> session handling.

=item session_store_class

The object store class that should be used for L<Apache::PageKit::Session> session handling.

=back

=head2 Other configuration variables

Global, server and page configuration variables are described in
the L<Apache::PageKit::Config> perldoc page.

=head1 REQUEST PARAMETERS

These are parameters that are specified in B<GET> requests and B<POST> requests where
I<Content-type> is one of I<application/x-www-form-urlencoded> or I<multipart/form-data>.

=over 4

=item pkit_credential_#

Login data, typically userid/login/email (pkit_credential_0) and
password (pkit_credential_1).

=item pkit_done

The page to return to after the user has finished logging in or creating a new account.

=item pkit_lang

Sets the user's preferred language, using a ISO 639 identifier.

=item pkit_login_page

This parameter is used to specify the page that user attempted to login from.
If the login fails, this page is redisplayed.

=item pkit_remember

If set to true upon login, will save user's cookie so that they are still logged
in next time they restart their browser.

=item pkit_view

Used to implement multiple views/co-branding.  For example, if set to I<print>,
will search for templates in the C<View/print> directory before using
templates in the C<View/Default> directory, and sets the
C<pkit_view:print> parameter in the view to true.

=back

=head1 SEE ALSO

L<Apache::PageKit::Config>,
L<Apache::PageKit::Content>,
L<Apache::PageKit::Error>,
L<Apache::PageKit::Model>, L<Apache::PageKit::View>,
L<Apache::Request>, L<HTML::FillInForm>, L<HTML::Template>,
L<HTML::FormValidator>

=head1 VERSION

This document describes Apache::PageKit module version 0.90

=head1 NOTES

Requires mod_perl, XML::Parser, HTML::Clean,
HTML::FillInForm, HTML::FormValidator, and HTML::Template.

I wrote these modules because I needed an application framework that was based
on mod_perl and seperated HTML from Perl.  HTML::Embperl, Apache::ASP 
and HTML::Mason are frameworks that work with mod_perl, but embed Perl code
in HTML.  The development was inspired in part by Webmacro, which
is an open-source Java servlet framework that seperates Code from HTML.

The goal is of these modules is to develop a framework that provides most of the
functionality that is common across dynamic web sites, including session management,
authorization, form validation, component design, error handling, and content management.

If you have used (or are considering using) these modules
to build a web site, please drop me a line with the URL
of your web site.  My e-mail is tj@anidea.com.  Thanks!

=head1 BUGS

This framework is in alpha stage.  The interface may change in later
releases.

Please submit any bug reports, comments, or suggestions to
tjmather@anidea.com, or join the Apache::PageKit
mailing list at http://lists.sourceforge.net/mailman/listinfo/pagekit-users

=head1 TODO

Associate sessions with authenticated user ID.

Add web based editing tools allowing authorized user to edit
View, Content and Configuration files

Add more tests to the test suite.

Make content sharable across pages.

Move Apache::PageKit::Error to seperate distribtuion.

Add <PKIT_SELFURL_WITHOUT:param1:param2> tag.

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 COPYRIGHT

Copyright (c) 2000, AnIdea Corporation.  All rights Reserved.  PageKit is a trademark
of AnIdea Corporation.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
