package Apache::PageKit::Config;

# $Id: Config.pm,v 1.2 2000/12/03 20:34:21 tjmather Exp $

use integer;
use strict;
use Apache::PageKit;
use XML::Parser;

use vars qw($page_id $ATTR_NAME $cur_config
	$global_attr $server_attr $page_attr $page_id_match $domain $mtime_hashref);

#$global_attr = {};
#$server_attr = {};
#$page_attr = {};
#$mtime_hashref = {};

sub new {
  my $class = shift;
  my $self = { @_ };
  unless (-d "$self->{'config_dir'}"){
    die "Config directory $self->{'config_dir'} doesn't exist";
  }
  $self->{'server'} ||= 'Default';
  bless $self, $class;
  my $reload = $self->get_server_attr('reload');
  $self->reload if $reload && $reload eq 'yes';
  return $self;
}

# checks to see if we have config data and is up to date, otherwise, load/reload
sub reload {
  my ($config) = @_;
  my $config_dir = $config->{config_dir};
  my $mtime = (stat "$config_dir/Config.xml")[9];
  unless(exists $mtime_hashref->{$config_dir} &&
	$mtime < $mtime_hashref->{$config_dir}){
    $config->parse_xml;
    $mtime_hashref->{$config_dir} = $mtime;
  }
}

sub parse_xml {
  my ($config) = @_;

  # set global variable so that XML::Parsers handlers can see it
  $cur_config = $config;

  # delete current init
  $page_id_match->{$config->{config_dir}} = {};
  $page_attr->{$config->{config_dir}} = {};

  my $p = XML::Parser->new(Style => 'Subs',
			   ParseParamEnt => 1,
			   NoLWP => 1);

  $p->setHandlers(Default => \&Default);
  $p->setHandlers(Attlist => \&Attlist);

  $p->parsefile("$config->{config_dir}/Config.xml");

  Apache::PageKit->call_plugins($config, 'info_init_handler');
}

# get rid of and just call template_file_exists
#sub page_exists {
#  my ($config, $page_id) = @_;
#  if (exists $page_attr->{$config->{config_dir}}->{$page_id}){
#    return 1;
#  } else {
#    my $view = $config->{pk}->{view};
#    return $view->template_file_exists($page_id);
#  }
#}

sub get_global_attr {
  my ($config, $key) = @_;
  return $global_attr->{$config->{config_dir}}->{$key};
}

sub get_server_attr {
  my ($config, $key) = @_;
  return $server_attr->{$config->{config_dir}}->{$config->{server}}->{$key};
}

# required page_id paramater
sub get_page_attr {
  my ($config, $page_id, $key) = @_;

  return unless $page_attr->{$config->{config_dir}}->{$page_id};
  return $page_attr->{$config->{config_dir}}->{$page_id}->{$key};
}

# optional page_id paramater
#sub get_param {
#  my ($config, $key, $page_id) = @_;
#  return unless $config->{pk};
#  $page_id ||= $config->{pk}->{page_id};
#  return unless $config->{param}->{$page_id};
#  return $config->{param}->{$page_id}->{$key};
#}

# optional page_id paramater
#sub get_param_hashref {
#  my ($config, $page_id) = @_;
#  return unless $config->{pk};
#  $page_id ||= $config->{pk}->{page_id};
#  return $config->{param}->{$page_id};
#}

sub page_id_by_domain {
  my ($config, $domain) = @_;
  return $domain->{$config->{config_dir}}->{$domain};
}

# used to match pages to regular expressions in the page_id_match column
sub page_id_match {
  my ($config, $page_id_in) = @_;
  my $page_id_out;
  while(my ($page_id, $reg_exp) = each %{$page_id_match->{$config->{config_dir}}}){
    my $match = '$page_id_in =~ /' . $reg_exp . '/';
    if(eval $match){
      $page_id_out = $page_id;
    }
  }
  return $page_id_out;
}

##################################
# methods for parsing XML file

#sub SITE {}
#sub SITE_ {}

# called at begining of <CONTENT> tag in XML file
#sub CONTENT {
#  my ($p, $edtype, %attr) = @_;
#  $page_id = $attr{page_id};
#}

#sub CONTENT_ {}

# called at <GLOBAL> tag in XML file
sub GLOBAL {
  my ($p, $edtype, %attr) = @_;

  while (my ($key, $value) = each %attr){
    $global_attr->{$cur_config->{config_dir}}->{$key} = $value;
  }
}

# called at <SERVER> tag in XML file
sub SERVER {
  my ($p, $edtype, %attr) = @_;

  my $config = $cur_config;
  my $server_id = $attr{server_id} || 'Default';
  while (my ($key, $value) = each %attr){
    $server_attr->{$config->{config_dir}}->{$server_id}->{$key} = $value;
  }
}

# called at beginning <PAGE> tag in XML file
sub PAGE {
  my ($p, $edtype, %attr) = @_;

  $page_id = $attr{page_id};
  my $config = $cur_config;

  if(my $sub_domain = $server_attr->{$config->{config_dir}}->{$config->{server}}->{sub_domain} && $attr{domain}){
    $attr{domain} =~ s/([^.]*)\.([^.]*)$/$sub_domain.$1.$2/;
  }

  while (my ($key, $value) = each %attr){
    next if $key eq 'page_id';
    if($key eq 'page_id_match'){
      $page_id_match->{$config->{config_dir}}->{$page_id} = $value;
    } else {
      $page_attr->{$config->{config_dir}}->{$page_id}->{$key} = $value;
      if($key eq 'is_topdomain' && $value eq 'yes'){
	$domain->{$config->{config_dir}}->{$attr{domain}} = $page_id;
      }
    }
  }
}

sub PAGE_ {}

# called at the beginning of ATTR tag in XML file
sub ATTR {
  my ($p, $edtype, %attr) = @_;

  $ATTR_NAME = $attr{NAME};
  $page_attr->{$cur_config->{config_dir}}->{$page_id}->{$ATTR_NAME} = "";
}

sub ATTR_ {
  $ATTR_NAME = undef;
}

sub Default {
  my ($p, $string) = @_;
  if($ATTR_NAME){
    $page_attr->{$cur_config->{config_dir}}->{$page_id}->{$ATTR_NAME} .= $string;
  }
}

sub Attlist {
  my ($p, $elname, $attname, $type, $default, $fixed) = @_;

  if($elname eq 'GLOBAL' && $default ne '#IMPLIED'){
#   print "hi $elname $attname $type $default\n";
    $global_attr->{$cur_config->{config_dir}}->{$attname} ||= $default;
  }
}

1;

=head1 NAME

Apache::PageKit::Config - Reads and provides configuration data.

=head1 SYNOPSIS

This is a wrapper class to the global, server and page
configuration settings stored in the
pagekit_root/Controller/Config.xml file.

=head1 METHODS

=over 4

=item new

Constructor method, takes configuration directory
and server as arguments.

  my $config = Apache::PageKit::Config->new(config_dir => $config_dir,
					server => $server);

If server is not specified, defaults to 'Default'.

=item parse_xml

Load settings from pagekit_root/Controller/Config.xml.

  $config->parse_xml;

=item get_global_attr

  $config->get_global_attr('fill_in_form');

Gets the global fill_in_form attribute.

=item get_server_attr

  $config->get_server_attr('cookie_domain');

Gets the cookie_domain attribute for the server associated with $config.

=item get_page_attr

  $config->get_page_attr($page_id,'use_nav');

Gets the value of the C<use_nav> attribute of C<$page_id>.

=back

=head1 CONFIGURATION VARIABLES

=head2 Global Attributes

These settings are global in the sense that they apply over all pages and servers.  They are attributes of the <GLOBAL> tag in Config.xml

=over 4

=item cookies_not_set_page

This is the page that gets displayed if the user attempts to log in,
but their cookies are not enabled.  Defaults to C<login_page>.

=item default_page

Default page user gets when no page is specified.  Defaults to I<index>.

=item fill_in_form

When set to 1, automatically fills in HTML forms with values from the C<$apr> 
(L<Apache::Request>) object.  Defaults to 1.

=item include_dispatch_prefix

This prefixes the class that the contains the include code.  Defaults to MyPageKit::IncludeCode.

Methods in this class must be named include_I<include_id> where I<include_id> is the ID of the include,
and take an Apache::PageKit object as their only argument.

=item login_page

Page that gets displayed when user attempts to log in.  Defaults to I<login>.

=item not_found_page

Error page when page cannot be found.  Defaults to C<default_page>.

=item page_dispatch_prefix

This prefixes the class that the contains the page code.  Defaults to MyPageKit::PageCode.

Methods in this class must be named page_I<page_id> where I<page_id> is the ID of the include,
and take an Apache::PageKit object as their only argument.

=item post_max

Maximum size of file uploads.  Defaults to 100,000,000 (100 MB).

=item recent_login_timeout

Seconds that user's session has to be inactive before a user is asked
to verify a password on pages with the C<require_login> attribute
set to I<recent>.  Defaults to 3600 (1 hour).

=item uri_prefix

Prefix of URI that should be trimmed before dispatching to the Page code.

=item verify_page

Verify password form.  Defaults to C<login_page>.

=back

=head2 Server Attributes

These options are global over all pages, but are local to each server configuration
(e.g. production, staging, development).  They are located in the <SERVERS>
tag of Config.xml

=over 4

=item cookie_domain

Domain for that cookies are issued.  Note that you must have
at least two periods in the cookie domain.

=item error_handler

Specifies the type of error handling.  I<email> e-mails the
server administrator, I<display> displays the error on the web page.
Defaults to I<none>.

=item files_match

  files_match = "\.html?$"

Declines requests that match value.

=item page_domain

If I<yes>, multiple domains are used for the site.  Domains
can be used to map to pages.  Default is I<no>.

=item reload

If set to I<yes>, check for new content and config xml files
on each request.  Should be set to I<no> on production servers.
Default is I<no>.

=item search_engine_headers

If set to I<yes>, sends I<Content-Length> and I<Last-Modified> headers
on pages that
don't require a login.  Some search engines might that these headers be set
in order to index a page.

META: I'm not sure if this works or is necessary with search engines.
Please send me any comments or suggestions.

Default is I<no>.

=item subdomain

  subdomain = "staging"

This specifies the subdomain under the domain that this particular
server is running.  Only needs to be set if C<page_domain> is set to I<yes>.

Used in development environments where the hostname is different
from the production environment.  For example www.mywebsite.com will
become www.staging.mywebsite.com under staging.

=back

=head2 Page Attributes

These options are local to each page on the site, but are global across each server.  The are located in the <PAGES> tag of Config.xml.

=over 4

=item page_id (required)

Page ID for this page.

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

=item internal_title

Title of page displayed on Content Management System. (Forthcoming)

=item is_popup

If set to I<yes>, links to this page popup a window using javascript.

=item is_secure

If set to I<yes>, links to this page will begin with C<https://>.

=item is_topdomain

If set to I<yes>, page will be the default page for the domain specified
in the C<domain> field.

=item nav_title

Title used in navigation bar - used in C<E<lt>TMPL_LOOP NAME="PKIT_NAV"E<gt> E<lt>/TMPL_LOOPE<gt>> tag.

=item new_credential

Should be set to I<yes> for pages that process credentials and update the
database, such as pages that process new registration and forms that set a new login and/or password.

If set to I<yes>, then it reissues the cookie that contains the credentials and
authenticates the user.

=item page_id_match

Value should be a regular expression.
Servers requests whose URL (after the host name) match the regular expression.
For example, C<^member\/\d*$> matches http://yourdomain.tld/member/4444.

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

If set to I<normal>, enables C<cache> option of L<HTML::Template> for the Page and Include templates.

If set to I<shared>, enables C<shared_cache> option of L<HTML::Template>.

=item use_nav

If set to I<yes>, creates navigation bar in location specified by
C<E<lt>TMPL_LOOP NAME="PKIT_NAV"E<gt> E<lt>/TMPL_LOOPE<gt>> in the template.

=item use_template

If set to I<yes>, uses HTML::Template files.  If set to I<no> page code
is responsible for sending output.  Default is I<yes>.

=back


=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 COPYRIGHT

Copyright (c) 2000, AnIdea Corporation.  All rights Reserved.  PageKit is
a trademark of AnIdea Corporation.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
