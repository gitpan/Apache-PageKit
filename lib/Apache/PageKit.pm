package Apache::PageKit;

# $Id: PageKit.pm,v 1.102 2001/07/14 14:32:55 tjmather Exp $

# required for UNIVERSAL->can
require 5.005;

use strict;

# CPAN Modules required for pagekit
use Apache::URI ();
use Apache::Cookie ();
use Apache::Request ();
use Apache::Util ();
use Compress::Zlib ();
use File::Find ();
use HTML::FillInForm ();
use HTML::Parser ();
use HTML::Template ();
use Mail::Mailer ();
use Text::Iconv ();
use XML::Parser ();

$| = 1;

# PageKit modules
use Apache::PageKit::Param ();
use Apache::PageKit::View ();
use Apache::PageKit::Content ();
use Apache::PageKit::Model ();
use Apache::PageKit::Session ();
use Apache::PageKit::Config ();

use Apache::Constants qw(OK DONE REDIRECT DECLINED);

use vars qw($VERSION);
$VERSION = '1.05';

%Apache::PageKit::DefaultMediaMap = (
				     pdf => 'application/pdf',
				     wml => 'text/vnd.wap.wml',
				     xml => 'application/xml');

# in httpd.conf file
sub startup ($$$) {
  my ($class, $pkit_root, $server) = @_;

  die 'must specify $server variable in startup.  Usage: Apache::PageKit->startup($pkit_root, $server)' unless $server;

  my $s = Apache->server;

  # get user and group as specified by User and Group directives
  my $uid = $s->uid;
  my $gid = $s->gid;

  # include user defined classes (Model) in perl search path
  unshift(@INC,"$pkit_root/Model");

  my $config_dir = $pkit_root . '/Config';

  my $config = Apache::PageKit::Config->new(config_dir => $config_dir,
					    server => $server);
  $config->parse_xml;
  my $cache_dir = $config->get_global_attr('cache_dir');
  my $view_cache_dir = $cache_dir ? $cache_dir . '/pkit_cache' :
    $pkit_root . '/View/pkit_cache';

  unless(-e "$view_cache_dir"){
    mkdir $view_cache_dir, 0755;
  }

  # User defined base model class
  my $model_base_class = $config->get_global_attr('model_base_class') || "MyPageKit::Common";
  eval "require $model_base_class";
  if($@){
    die "Failed to load $model_base_class - looked in $pkit_root/Model ($@)";
  }

  # delete all cache files, since some of them might be stale
  # and might not be checked for freshness, if reload is off
  # even if reload is on, PageKit might change, so it should be refreshed
  my $unlink_sub = sub {
    -f && unlink;
  };
  File::Find::find($unlink_sub,$view_cache_dir);
  $model_base_class->pkit_startup($pkit_root, $server, $config)
    if $model_base_class->can('pkit_startup');
}

# object oriented method call, see Eagle p.65
sub handler ($$){
  my $class = shift;

  my ($pk, $status_code);

  $| = 1;

  eval {
    $pk = $class->new;
    my $model = $pk->{model};
    my $apr = $pk->{apr};
    my $view = $pk->{view};
    my $config = $pk->{config};
    $status_code = $pk->prepare_page;
    my $use_template = $config->get_page_attr($pk->{page_id},'use_template') || 'yes';
    if ($status_code eq OK && $use_template ne 'no'){
      $pk->open_view;
      for my $component_id (@{$view->{record}->{component_ids}}){
	$pk->component_code($component_id);
      }
      $model->pkit_post_common_code if $model->can('pkit_post_common_code');
      $pk->set_session_cookie;
      $pk->prepare_and_print_view;
    }
    $model->pkit_cleanup_code if $model->can('pkit_cleanup_code');
  };
  if($@){
    if($pk){
      $pk->fatal_error($@);
    } else {
      if(exists $INC{'Apache/ErrorReport.pm'}){
	Apache::ErrorReport::fatal($@);
      }
      die $@;
    }
  }

  delete $pk->{session};
  return $status_code;
}

# called in case die is trapped by eval
sub fatal_error {
  my ($pk, $error) = @_;
  delete $pk->{session};
  my $model = $pk->{model};
  $model->pkit_cleanup_code if $model->can('pkit_cleanup_code');
  if(exists $INC{'Apache/ErrorReport.pm'}){
    Apache::ErrorReport::fatal($error);
  }
  die $error;
}

# utility function, concats parameters from request parameters into string
# seperated by '&' and '=' - suitable for displaying in a URL
sub params_as_string {
  my ($apr, $exclude_param) = @_;

  my $args;
  # we cache args in pnotes - i think it is faster this way
  # especially if you have <PKIT_SELFURL exclude="foo"> tags
  unless ($args = $apr->pnotes('r_args')){
    my %args = $apr->args;
    for (qw(login logout view check_cookie messages error_messages lang)){
      delete $args{"pkit_$_"};
    }
    $args = \%args;
    $apr->pnotes(r_args => $args);
  }

  if($exclude_param && @$exclude_param){
    my %exclude_param_hash = map {$_ => 1} @$exclude_param;
    return join ('&', map { Apache::Util::escape_uri("$_") ."=" . Apache::Util::escape_uri($args->{$_} || "")} grep {!exists $exclude_param_hash{$_}} keys %$args);
  } else {
    return join ('&', map { Apache::Util::escape_uri("$_") ."=" . Apache::Util::escape_uri($args->{$_} || "")} keys %$args);
  }
}

sub update_session {
  my ($pk, $auth_session_id) = @_;
  # keep recent sessions recent, if user is logged in
  # that is sessions time out if user hasn't viewed in a page
  # in recent_login_timeout seconds
  my $session = $pk->{session};
  return unless defined($session);

  unless(exists($session->{pkit_inactivity_timeout})){
    my $recent_login_timeout = $pk->{config}->get_global_attr('recent_login_timeout');
    my $last_activity = $session->{pkit_last_activity};
    if(defined($recent_login_timeout) && defined($last_activity) &&
       $last_activity + $recent_login_timeout < time()){
      # user has been inactive for recent_login_timeout seconds, timeout
      $session->{pkit_inactivity_timeout} = 1;
    } else {
      # update last_activity timestamp
      $session->{pkit_last_activity} = time();
    }
  }
}

sub prepare_page {
  my $pk = shift;

  # $apr is an Apache::Request object, derived from Apache request object
  my $apr = $pk->{apr};

  # $view is an Apache::PageKit::View object
  my $view = $pk->{view};

  # $config is an Apache::PageKit::Config object
  my $config = $pk->{config};

  # $model is an Apache::PageKit::Model object
  my $model = $pk->{model};

  # decline to serve images, etc
#  return DECLINED if $apr->content_type && $apr->content_type !~ m|^text/|io;

  my $uri = $apr->uri;

  # decline files_match
  if (my $files_match = $config->get_server_attr('files_match')){
    return DECLINED if $uri =~ m/$files_match/;
  }

  my $uri_prefix = $config->get_global_attr('uri_prefix');

  if($uri_prefix){
    $uri =~ s(^/$uri_prefix)(/);
  }

  if($model->can('pkit_fixup_uri')){
    $uri = $model->pkit_fixup_uri($uri);
  }

#  my $host = (split(':',$apr->headers_in->{'Host'}))[0];
  my ($host, $uri_with_query);
  if(my $X_Original_URI = $apr->headers_in->{'X-Original-URI'}){
    ($host) = ($X_Original_URI =~ m!^https?://([^/]*)!);
    $uri_with_query = $X_Original_URI;
  } else {
    $host = $apr->headers_in->{'Host'};

    $uri_prefix =~ s!/$!!g;
    $uri_with_query = (($ENV{HTTPS} eq 'on') ? 'https' : 'http') . '://' . $host . ($uri_prefix ? '/' . $uri_prefix : '' ) . $uri;
  }
#  my $pkit_selfurl;

  $apr->notes(orig_uri => $uri_with_query);

  my $query_string = params_as_string($apr);
  if($query_string){
    $uri_with_query .= "?" . $query_string;
#    $pkit_selfurl = $uri_with_query . '&';
#  } else {
#    $pkit_selfurl = $uri_with_query . '?';
  }
#  $view->param(PKIT_SELFURL => $pkit_selfurl);

  my $output_param_object = $pk->{output_param_object};
  my $fillinform_object = $pk->{fillinform_object};

  $output_param_object->param(PKIT_HOSTNAME => $host);

#  my $pkit_done = Apache::Util::escape_uri($apr->param('pkit_done') || $uri_with_query);
  my $pkit_done = $apr->param('pkit_done') || $uri_with_query;

#  $pkit_done =~ s/"/\%22/g;
#  $pkit_done =~ s/&/\%26/g;
#  $pkit_done =~ s/\?/\%3F/g;
  $output_param_object->param("pkit_done",$pkit_done);
#  $fillinform_object->param("pkit_done",$pkit_done);

  $pk->{page_id} = $uri;

  # get rid of leading forward slash
  $pk->{page_id} =~ s(^/+)();

  # add index for pageid with trailing slash "/"
  # WARNING - this is undocumented and may go away at anytime
  $pk->{page_id} =~ s!(.+)/$!$1/index!;

  # get default page if there is no page specified in url
  if($pk->{page_id} eq ''){
    $pk->{page_id} = $model->pkit_get_default_page;
  }

  # redirect "not found" pages
  unless ($pk->page_exists($pk->{page_id})){
    # first try to see if we can find a static file that we
    # can return
    my $filename = $pk->static_page_exists($pk->{page_id});
    unless($filename){
      $pk->{page_id} = ($config->uri_match($pk->{page_id})
	|| $config->get_global_attr('not_found_page'))
	  || $model->pkit_get_default_page;
      unless ($pk->page_exists($pk->{page_id})){
	# if not_found_page is static, the return DECLINED...
	$filename = $pk->static_page_exists($pk->{page_id});
      }
    }
    if ($filename){
      require MIME::Types;
      my ($media_type, $content_encoding) = MIME::Types::by_suffix($filename);
      $apr->content_type($media_type);
      if($media_type eq "text/html" && $pk->{use_gzip}){
        my $gzipped = $view->get_static_gzip($filename);
        if ($gzipped){
          $apr->content_encoding("gzip");
          $apr->send_http_header;
          $apr->print($gzipped);
          return DONE;
        }
      }

      # set path_info to '', otherwise Apache tacks it on at the end
      $apr->path_info('');
      $apr->filename($filename);
      return DECLINED;
    }
  }

  my ($auth_user, $auth_session_id);
  if($apr->param('pkit_logout')){
    $pk->logout;
    $apr->param('pkit_check_cookie','');
    # goto home page when user logouts (if from page that requires login) 
    my $require_login = $config->get_page_attr($pk->{page_id},'require_login');
    if (defined($require_login) && $require_login =~ m!^(yes|recent)$!){
      $pk->{page_id} = $config->get_global_attr('default_page');
    }
    $model->pkit_message("You have successfully logged out.");
  } else {
    ($auth_user, $auth_session_id) = $pk->authenticate;
  }

  # session handling
  if($model->can('pkit_session_setup')){
    $pk->setup_session($auth_session_id);
  }
  my $session = $pk->{session};

  if($apr->param('pkit_login')){
    if ($pk->login){
      # if login is sucessful, redirect to (re)set cookie
      return REDIRECT;
    } else {
      # else return to login form
#      my $referer = $apr->header_in('Referer');
#      $referer =~ s(http://[^/]*/([^?]*).*?)($1);
      $pk->{page_id} = $apr->param('pkit_login_page') || $config->get_global_attr('login_page');
    }
  }

  if($auth_user){
    my $pkit_check_cookie = $apr->param('pkit_check_cookie');
    if(defined($pkit_check_cookie) && $pkit_check_cookie eq 'on'){
      $model->pkit_message("You have successfully logged in.");
    }
    $pk->update_session($auth_session_id);

    my $require_login = $config->get_page_attr($pk->{page_id},'require_login');
    if(defined($require_login) && $require_login eq 'recent'){
      if(exists($session->{pkit_inactivity_timeout})){
	# user is logged in, but has had inactivity period

	# display verify password form
	$pk->{page_id} = $config->get_global_attr('verify_page') ||
	  $config->get_global_attr('login_page');
	# pkit_done parameter is used to return user to page that they originally requested
	# after login is finished
	$output_param_object->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");

#	$apr->connection->user(undef);
      }
    }
  } else {
    # check if cookies should be set
    my $pkit_check_cookie = $apr->param('pkit_check_cookie');
    if(defined($pkit_check_cookie) && $pkit_check_cookie eq 'on'){
      # cookies should be set but aren't.
      if($config->get_global_attr('cookies_not_set_page')){
	# display "cookies are not set" error page.
	$pk->{page_id} = $config->get_global_attr('cookies_not_set_page');
      } else {
	# display login page with error message
	$pk->{page_id} = $config->get_global_attr('login_page');
	$model->pkit_message("Cookies must be enabled in your browser.",
		    is_error => 1);
      }
    }

    my $require_login = $config->get_page_attr($pk->{page_id},'require_login');
    if(defined($require_login) && $require_login =~ /^(yes|recent)$/){
      # this page requires that the user has a valid cookie
      $pk->{page_id} = $config->get_global_attr('login_page');
      $output_param_object->param("pkit_done",$uri_with_query) unless $apr->param("pkit_done");
      $model->pkit_message("This page requires a login.");
      $pk->logout;
    }
  }

  # get language
  # get Locale settings
  my ($lang, $accept_lang);

  if($lang = $apr->param('pkit_lang')){
    $session->{'pkit_lang'} = $lang if $session;
  } elsif ($session && ! exists $pk->{is_new_session}){
    $lang = $session->{'pkit_lang'} if exists $session->{'pkit_lang'};
  } else {
    unless ($lang = substr($apr->header_in('Accept-Language'),0,2)){
      $lang = $config->get_global_attr('default_lang') || 'en';
    }
  }

  # TEMP only for anidea.com site, until fix problems with localization in content
  $output_param_object->param("PKIT_LANG_$lang" => 1);

  $pk->{lang} = $lang;

  $model->pkit_common_code if $model->can('pkit_common_code');

  # run the page code!
  my $status_code = $pk->page_code;
  $status_code ||= $pk->{status_code};
  if(defined($status_code) && ($status_code eq REDIRECT || $status_code eq DONE)){
    return $status_code;
  }

  # add pkit_message from previous page, if that pagekit did a pkit_redirect
  if(my @pkit_messages = $apr->param('pkit_messages')){
    for my $message (@pkit_messages){
      $model->pkit_message($message);
    }
  }
  if(my @pkit_error_messages = $apr->param('pkit_error_messages')){
    for my $message (@pkit_error_messages){
      $model->pkit_message($message, is_error => 1);
    }
  }

  # deal with different views
  if(my $pkit_view = $apr->param('pkit_view')){
    $output_param_object->param('pkit_view:' . $pkit_view => 1);
  }

  return OK;
}

sub _check_gzip {
  my $pk = shift;
  # check Accent-Encoding or if the user_agent field for Unix/Mac Netscape
  # to see if should gzip output
  my $gzip_output = $pk->{config}->get_global_attr("gzip_output") || "";
  my $apr = $pk->{apr};
  if ($gzip_output =~ m!^(all|static)$!){
    if(($apr->header_in("Accept-Encoding") || "") =~ /gzip/){
      $pk->{use_gzip} = $gzip_output;
    } else {
      my $user_agent = $apr->header_in("User-Agent");
      # this regular expression borrowed from Apache::AxKit::ConfigReader::DoZip
      if ($user_agent =~ m{
			   ^Mozilla/
			   \d+
			   \.
			   \d+
			   [\s\[\]\w\-]+
			   (
			    \(X11 |
			    Macint.+PPC,\sNav
			   )
			  }x
	 ) {
	$pk->{use_gzip} = $gzip_output;
      }
    }
  }
}

sub open_view {
  my ($pk) = @_;

  my $pkit_view = $pk->{apr}->param('pkit_view') || 'Default';

  # open template file
  $pk->{view}->open_view($pk->{page_id}, $pkit_view, $pk->{lang});
}

sub prepare_and_print_view {
  my ($pk) = @_;

  my $apr = $pk->{apr};
  my $view = $pk->{view};
  my $config = $pk->{config};
  my $model = $pk->{model};

  my $page_id = $pk->{page_id};

  # set view fillinform_objects and associated_objects, if approriate
  my $fill_in_form = $config->get_page_attr($page_id,'fill_in_form') || 'yes';
  if($fill_in_form ne 'no'){
    # $apr comes first, so that fillinform overrides request parameters
    $view->{fillinform_objects} = [$apr, $pk->{fillinform_object}];
  } else {
    $view->{fillinform_objects} = [$pk->{fillinform_object}];
  }
  my $page_rpit = $config->get_page_attr($page_id,'request_param_in_tmpl') || '';
  my $global_rpit = $config->get_global_attr('request_param_in_tmpl') || 'no';
  if($page_rpit eq 'yes' || ($page_rpit ne 'no' &&
     $global_rpit eq 'yes')){
    $view->{associated_objects} = [$apr];
  }

  # set up page template and run component code
  my $output_ref = $view->fill_in_view;

  # determine output media type
  my $pkit_view = $apr->param('pkit_view') || 'Default';
  my $output_media = $config->get_view_attr($pkit_view, 'output_media') ||
    $config->get_page_attr($page_id, 'output_media');

  $output_media ||= $Apache::PageKit::DefaultMediaMap{$pkit_view};
  $output_media ||= 'text/html';

  # set expires to now so prevent caching
  #$apr->no_cache(1) if $apr->param('pkit_logout') || $config->get_page_attr($pk->{page_id},'template_cache') eq 'no';
  # see http://support.microsoft.com/support/kb/articles/Q234/0/67.ASP
  # and http://www.pacificnet.net/~johnr/meta.html
  my $browser_cache =  $config->get_page_attr($page_id,'browser_cache') || 'yes';
  $apr->header_out('Expires','-1') if $apr->param('pkit_logout') || $browser_cache eq 'no' || $apr->connection->user;

  my $retcharset;
  my $default_output_charset = $view->{default_output_charset};
  my @charsets = ();
  if($output_media eq 'text/html'){
    # first get accepted charsets from incoming Accept-Charset HTTP header
    if(my $accept_charset = $apr->headers_in->{'Accept-Charset'}){
      my $pos = 0;
      foreach my $charset (split(/,\s*/, $accept_charset)) {
        my $score;

        ($charset, $score) = split(/;\s*q=/, $charset, 2);
        $score = 1 unless (defined($score) && ($score =~ /^(\+|\-)?\d+(\.\d+)?$/));
        $charset =~ s/iso/ISO/;
        $charset =~ s/utf/UTF/;
        $charset =~ s/(us\-)?ascii/US-ASCII/;
        push @charsets, [ $charset, $score, $pos++ ];
      }
      @charsets = sort {$b->[1] <=> $a->[1] || $a->[2] <=> $b->[2] } @charsets;
      # set a content-type perhaps we overwrite this later if we know about the charset for the output pages
      $apr->content_type("text/html");
    }
  } elsif ($output_media eq 'application/pdf'){
    # write output_media to file, using process number of Apache child process
    my $view_cache_dir = $view->{cache_dir};

    my $fo_file = "$view_cache_dir/$$.fo";
    my $pdf_file = "$view_cache_dir/$$.pdf";
    open FO_TEMPLATE, ">$fo_file";
    print FO_TEMPLATE $$output_ref;
    close FO_TEMPLATE;

    # call Apache XML FOP
    my $fop_command = $config->get_server_attr('fop_command') ||
      $config->get_global_attr('fop_command');
    die "fop_command not specifed in configuration - must specify to use Apache XML FOP to generate PDFs" unless $fop_command;
    my $error_message = `$fop_command $fo_file $pdf_file 2>&1 1>/dev/null`;

    if(-s "$pdf_file"){
      $$output_ref = "";

      open PDF_OUTPUT, "$pdf_file";
      while(<PDF_OUTPUT>){
	$$output_ref .= $_;
      }
      close PDF_OUTPUT;
    } else {
      die "Error processing template with Apache XML FOO: $error_message";
    }
    $apr->content_type($output_media);
  } else {
    # just set content_type
    $apr->content_type($output_media);
  }

  if($pk->{use_gzip} eq 'all'){
    $apr->content_encoding("gzip");
  }

  # for a head request
  if ($apr->header_only) {
    $apr->send_http_header if $apr->is_initial_req;
    return;
  }

  # call output filter, if applicable
  $model->pkit_output_filter($output_ref)
    if $model->can('pkit_output_filter');

  my $converted_data;
  if ($output_media eq 'text/html'){
    my $data;
    while (@charsets){
      $retcharset = (shift @charsets)->[0];
      last if ($retcharset eq $default_output_charset);
      eval {
        my $converter = Text::Iconv->new($default_output_charset, $retcharset);
        $converted_data = $converter->convert($$output_ref);
      };
      last if ($converted_data);
      $retcharset = undef;
    }

    # correct the header
    $apr->content_encoding('') unless ($retcharset);
    $apr->content_type("text/html; charset=$retcharset") if ($retcharset);
    $apr->content_type("text/html")                      unless ($retcharset);
  }

  $apr->send_http_header if $apr->is_initial_req;

  if($converted_data){
    if($pk->{use_gzip} eq 'all'){
      $apr->print(Compress::Zlib::memGzip($converted_data));
    } else {
      $apr->print($converted_data);
    }
  } else {
    if($pk->{use_gzip} eq 'all' && $retcharset){
      $apr->print(Compress::Zlib::memGzip($$output_ref));
    } else {
      $apr->print($$output_ref);
    }
  }
}

sub new {
  my $class = shift;

  my $r = Apache->request;
  my $self = {@_};

  bless $self, $class;

  # set up contained objects
  my $pkit_root = $r->dir_config('PKIT_ROOT');
  die "Must specify PerlSetVar PKIT_ROOT in httpd.conf file" unless $pkit_root;
  my $config_dir = $pkit_root . '/Config';
  my $content_dir = $pkit_root . '/Content';
  my $view_dir = $pkit_root . '/View';
  my $server = $r->dir_config('PKIT_SERVER');
  die "Must specify PerlSetVar PKIT_SERVER in httpd.conf file" unless $server;
  my $config = $self->{config} = Apache::PageKit::Config->new(config_dir => $config_dir,
						 server => $server);
  my $apr = $self->{apr} = Apache::Request->new($r, POST_MAX => $self->{config}->get_global_attr('post_max'));
  my $model_base_class = $self->{config}->get_global_attr('model_base_class') || "MyPageKit::Common";

  my $model;
  eval {$model = $self->{model} = $model_base_class->new(pkit_pk => $self)};
  if($@){
    unless($model_base_class){
      die "model_base_class not specified";
    } else {
      die "Model class $model_base_class has no new method";
    }
  }

  $self->{dbh} = $model->pkit_dbi_connect if $model->can('pkit_dbi_connect');

  my $default_lang = $config->get_global_attr('default_lang') || 'en';
  my $default_input_charset = $config->get_global_attr('default_input_charset') || 'ISO-8859-1';
  my $default_output_charset = $config->get_global_attr('default_output_charset') || 'ISO-8859-1';
  my $html_clean_level = $config->get_server_attr('html_clean_level');
  my $can_edit = $config->get_server_attr('can_edit');
  my $reload = $config->get_server_attr('reload');

  my $cache_dir = $config->get_global_attr('cache_dir');
  my $view_cache_dir = $cache_dir ? $cache_dir . '/pkit_cache' :
    $pkit_root . '/View/pkit_cache';

  $self->{view} = Apache::PageKit::View->new(view_dir => "$pkit_root/View",
					     content_dir => "$pkit_root/Content",
					     cache_dir => $view_cache_dir,
					     default_lang => $default_lang,
					     default_input_charset => $default_input_charset,
					     default_output_charset => $default_output_charset,
					     reload => $reload,
					     html_clean_level => $html_clean_level,
					     input_param_object => $apr,
					     output_param_object => $self->{output_param_object},
					     can_edit => $can_edit,
					    );

  return $self;
}

sub page_sub {
  my $pk = shift;
  my $page_id = shift || $pk->{page_id};

  # change all the / to ::
  $page_id =~ s!/!::!g;

  my $perl_sub;
  if($page_id =~ s/^pkit_edit:://){
    $perl_sub = 'Apache::PKCMS::Edit::' . $page_id;
  } else {
    my $model_dispatch_prefix = $pk->{config}->get_global_attr('model_dispatch_prefix');
    $perl_sub = $model_dispatch_prefix . '::' . $page_id;
  }

  return $perl_sub if defined &{$perl_sub};

  my ($class_package) = $perl_sub =~ m/^(.*)::/;
  return if exists $Apache::PageKit::checked_classes{$class_package};

  eval "require $class_package";

  $Apache::PageKit::checked_classes{$class_package} = 1;

  return undef unless (defined &{$perl_sub});

  my $model_base_class = $pk->{config}->get_global_attr('model_base_class') || "MyPageKit::Common";

  warn qq{For full preformance please add "use $class_package" in your $model_base_class or startup.pl script\n};

  return $perl_sub;
}

sub page_code {
  my $pk = shift;
  my $perl_sub = $pk->page_sub;
  no strict 'refs';
  if ($perl_sub){
    return $pk->call_model_code($perl_sub);
  } else {
    return 1;
  }
}

sub component_code {
  my $pk = shift;
  my $component_id = shift;

  # change all the / to ::
  $component_id =~ s!/!::!g;

  # insert a module_ before the method
#  $component_id =~ s/(.*?)([^:]+)$/$1::$2/;

  my $model_dispatch_prefix = $pk->{config}->get_global_attr('model_dispatch_prefix');

  no strict 'refs';
  my $perl_sub = $model_dispatch_prefix . '::' . $component_id;

  if (defined &{$perl_sub}){
    return $pk->call_model_code($perl_sub);
  } else {
    return 1;
  }
}

# calls code from user module in Model
sub call_model_code {
  my ($pk, $perl_sub) = @_;

  my $model = $pk->{model};

  # extract class and method from perl subroutine
  my ($model_class, $method) = ($perl_sub =~ m!^(.+?)::([^:]+)$!);

  my $dispatch_model = $model->create($model_class);

  # dispatch message to model class
  no strict 'refs';
  return &{$model_class . '::' . $method}($dispatch_model);
}

sub login {
  my ($pk) = @_;

  my $apr = $pk->{apr};
  my $config = $pk->{config};
  my $session = $pk->{session};
  my $model = $pk->{model};

  my $remember = $apr->param('pkit_remember');
  my $done = $apr->param('pkit_done') || $apr->notes('orig_uri');

  unless($done){
    $model->pkit_get_default_page;
  }

  unless($model->can('pkit_auth_credential')){
    die "Must set pkit_auth_credential in your model base class";
  }
  my $ses_key = $model->pkit_auth_credential;

  $ses_key || return 0;

  # allow user to view pages with require_login eq 'recent'
  if(exists $pk->{session}){
    unless($pk->{is_new_session}){
      delete $pk->{session}->{pkit_inactivity_timeout};
      $pk->{session}->{pkit_last_activity} = time();
      # save session
      delete $pk->{session};
    }
  }

  my $cookie_domain_str = $config->get_server_attr('cookie_domain');
  my @cookie_domains = defined($cookie_domain_str) ? split(' ',$cookie_domain_str) : (undef);
  for my $cookie_domain (@cookie_domains){
    my $cookie = Apache::Cookie->new($apr,
				   -name => 'pkit_id',
				   -value => $ses_key,
				   -path => "/");
    $cookie->domain($cookie_domain) if $cookie_domain;
    if ($remember){
      $cookie->expires("+10y");
    }
    $cookie->bake;
  }

  # this is used to check if cookie is set
  if($done =~ /\?/){
    $done .= "&pkit_check_cookie=on";
  } else {
    $done .= "?pkit_check_cookie=on";
  }

  $done =~ s/ /+/g;

  if(my @pkit_messages = $apr->param('pkit_messages')){
    for my $message (@pkit_messages){
      $done .= "&pkit_messages=" . Apache::Util::escape_uri($message);
    }
  }
  if(my @pkit_error_messages = $apr->param('pkit_error_messages')){
    for my $message (@pkit_error_messages){
      $done .= "&pkit_error_messages=" . Apache::Util::escape_uri($message);
    }
  }

  $apr->headers_out->set(Location => "$done");
  return 1;
}

sub authenticate {
  my ($pk) = @_;
  my $apr = $pk->{apr};

  my $model = $pk->{model};

  my %cookies = Apache::Cookie->fetch;

  return unless $cookies{'pkit_id'};

  my %ticket = $cookies{'pkit_id'}->value;

  # in case pkit_auth_session_key is not defined, but cookie
  # is somehow already set
  return unless $model->can('pkit_auth_session_key');

  my ($auth_user, $auth_session_id) = $model->pkit_auth_session_key(\%ticket);

  return unless $auth_user;

  $auth_session_id = $auth_user
    unless defined($auth_session_id);

  $apr->connection->user($auth_user);
#  $apr->param(pkit_user => $auth_user);

#  $pk->{output_param_object}->param(pkit_user => $auth_user);

  return ($auth_user, $auth_session_id);
}

sub logout {
  my ($pk) = @_;

  my %cookies = Apache::Cookie->fetch;

  return unless defined $cookies{'pkit_id'};

  my $cookie_domain = $pk->{config}->get_server_attr('cookie_domain');
  my @cookie_domains = defined($cookie_domain) ? split(' ',$cookie_domain) :
    (undef);
  for my $cookie_domain (@cookie_domains){
    my $tcookie = $cookies{'pkit_id'};
    $tcookie->value("");
    $tcookie->path("/");
    $tcookie->domain($cookie_domain) if $cookie_domain;
    $tcookie->expires('-5y');
    $tcookie->bake;
  }
}

# get session_id from cookie
sub setup_session {
  my ($pk, $auth_session_id) = @_;

  my $model = $pk->{model};

  my $ss = $model->pkit_session_setup;
  unless($ss->{session_store_class} && $ss->{session_lock_class}){
    warn "failed to set up session - session_store_class and session_lock_class must be defined";
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

  $session_id ||= $auth_session_id;

  # this sets a flag so we know if we should send a cookie later...
  $pk->{is_new_session} = 1 unless $session_id;

  # set up session handler class
  my %session;

  my $session_lock_class = $ss->{session_lock_class};
  my $session_store_class = $ss->{session_store_class};
  tie %session, 'Apache::PageKit::Session', $session_id,
  {
   Lock => $session_lock_class,
   Store => $session_store_class,
   Generate => 'MD5',
   Serialize => 'Storable',
   create_unknown => 1,
   lazy => 1,
   %{$ss->{session_args}}
  };

  if(defined($auth_session_id) &&
     $auth_session_id ne $session_id){

    # permanently remove old session from storage
    tied(%session)->delete;
    untie(%session);

    my %auth_session;
    # get new session assoc with login
    tie %auth_session, 'Apache::PageKit::Session', $auth_session_id,
    {
     Lock => $session_lock_class,
     Store => $session_store_class,
     Generate => 'MD5',
     Serialize => 'Storable',
     create_unknown => 1,
     lazy => 1,
     %{$ss->{session_args}}
    };

    # user must have just logged in, so we must merge session objects!
    $pk->{model}->pkit_merge_sessions(\%session,\%auth_session);

    undef(%session);

    # unset cookie for old session
    my @cookie_domains = split(' ',$pk->{config}->get_server_attr('cookie_domain'));
    @cookie_domains = (undef) if @cookie_domains == 0;
    for my $cookie_domain (@cookie_domains){
      my $cookie = Apache::Cookie->new($apr,
					 -name => 'pkit_session_id',
					 -value => "",
					 -path => "/");
      $cookie->domain($cookie_domain) if $cookie_domain;
      $cookie->expires('-5y');
      $cookie->bake;
    }
    $pk->{session} = \%auth_session;
  } else {
    $pk->{session} = \%session;
  }
}

sub set_session_cookie {
  my ($pk) = @_;

  return unless exists $pk->{is_new_session};

  my $session = $pk->{session};
  my $apr = $pk->{apr};

  if(my $session_id = tied(%$session)->getid){
    # something was stored in session
    my $expires = $pk->{config}->get_global_attr('session_expires');
    my @cookie_domains = split(' ',$pk->{config}->get_server_attr('cookie_domain'));
    @cookie_domains = (undef) if @cookie_domains == 0;
    for my $cookie_domain (@cookie_domains){
      my $cookie = Apache::Cookie->new($apr,
				       -name => 'pkit_session_id',
				       -value => $session_id,
				       -path => "/");
      $cookie->domain($cookie_domain) if $cookie_domain;
      $cookie->expires($expires) if $expires;
      $cookie->bake;
    }
    # save for logging purposes (warning, undocumented and might go away)
    $apr->notes(pkit_session_id => $session_id);
  }
}

# check to see if page has either template or perl code associated with it
sub page_exists{
  my ($pk, $page_id) = @_;

  # check to see if template file exists
  my $pkit_view = $pk->{apr}->param('pkit_view') || 'Default';
  return 1 if $pk->{view}->template_file_exists($page_id, $pkit_view);

  # check to see if perl subroutine for page exists
  return 1 if $pk->page_sub;

  # check to see if content file exists
  my $pkit_root = $pk->{apr}->dir_config('PKIT_ROOT');
  return 1 if (-f "$pkit_root/Content/$page_id.xml");
}

sub static_page_exists{
  my ($pk, $page_id) = @_;
  my $apr = $pk->{apr};
  foreach ($apr->param('pkit_view'), 'Default') {
    if (defined ($_)){
      my $filename = $apr->dir_config('PKIT_ROOT') . '/View/' . $_ . '/' . $page_id;
      return $filename if (-e "$filename");
    }
  }
  return undef;
}

1;

__END__

=head1 NAME

Apache::PageKit - MVCC web framework using mod_perl, XML and HTML::Template

=head1 SYNOPSIS

In httpd.conf

  SetHandler perl-script
  PerlSetVar PKIT_ROOT /path/to/pagekit/files

  PerlHandler +Apache::PageKit
  <Perl>
        Apache::PageKit->startup("/path/to/pagekit/files");
  </Perl>

In MyPageKit/Common.pm

  package MyPageKit::Common;

  use base 'Apache::PageKit::Model';

  sub pkit_dbi_connect {
    return DBI->connect("DBI:mysql:db","user","passwd");
  }

  sub pkit_session_setup {
    my $model = shift;
    my $dbh = $model->dbh;
    return {
	session_lock_class => 'MySQL',
	session_store_class => 'MySQL',
	session_args => {
			Handle => $dbh,
			LockHandle => $dbh,
			},
	};
  }

  sub pkit_auth_credential {
    my ($model) = @_;

    # in this example, login and passwd are the names of the credential fields
    my $login = $model->input('login');
    my $passwd = $model->input('passwd');

    # create a session key
    # your code here.........

    return $ses_key;
  }

  sub pkit_auth_session_key {
    my ($model, $ses_key) = @_;

    # check whether $ses_key is valid, if so return user id in $user_id
    # your code here.........

    return $ok ? $user_id : undef;
  }

=head1 DESCRIPTION

PageKit is an mod_perl based application framework that uses HTML::Template and
XML to separate code, design, and content. Includes session management,
authentication, form validation, co-branding, and a content management system.

Its goal is to solve all the common problems of web programming, and to make
the creation and maintenance of dynamic web sites fast, easy and enjoyable.

You have to write a module named MyPageKit::Common
that inherits from Apache::PageKit::Model and
provides methods common across the site.
For example, if you wish to support authentication, it must
include the two methods C<pkit_auth_credential> and C<pkit_auth_session_key>.

For more information, visit http://www.pagekit.org/

Most of the docs have been moved out of POD to DocBook.  The sources can
be found in the docsrc directory of the distribution, and the HTML output
can be found at http://www.pagekit.org/guide

=head1 METHODS

The following method is available to the user as Apache::PageKit API.

=over 4

This function should be called at server startup from your httpd.conf file:

  <Perl>
        Apache::PageKit->startup("/path/to/pagekit/files","staging");
  </Perl>

Where the first argument is the root directory of the
PageKit application.  The second (optional) argument is the server id.
It loads /path/to/pagekit/files/Model into the perl search
path so that PageKit can make calls into MyPageKit::Common and
other Model classes.  It also loads
the Config and Content XML files and pre-parses the View template files.

=back

=head1 FREQUENTLY ASKED QUESTIONS

See http://www.pagekit.org/faq.html

=head1 SEE ALSO

L<Apache::Request>, L<HTML::FillInForm>, L<HTML::Template>,
L<Data::FormValidator>

=head1 VERSION

This document describes Apache::PageKit module version 1.05

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

Support Template-Toolkit templates as well as HTML::Template templates.

Support for exposing Model objects using XML-RPC and/or SOAP.

Support for multiple transformations with stylesheets, and for filters.

Associate sessions with authenticated user ID.

Add more tests to the test suite.

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 CREDITS

Fixes, Bug Reports, Docs have been generously provided by:

  Boris Zentner
  Ben Ausden
  Stu Pae
  Yann Kerhervé
  Chris Burbridge
  Leonardo de Carvalho
  Rob Falcon
  Sheffield Nolan
  David Raimbault

Also, thanks to Dan Von Kokorn for helping shape the initial architecture
and for the invaluable support and advice. 

=head1 COPYRIGHT

Copyright (c) 2000, 2001 AnIdea Corporation.  All rights Reserved.  PageKit is a trademark
of AnIdea Corporation.

Parts of code Copyright (c) 2000, 2001 AxKit.com Ltd.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license.html

=cut
