package Apache::PageKit::Config;

# $Id: Config.pm,v 1.9 2001/01/23 03:40:21 tjmather Exp $

use integer;
use strict;
use Apache::PageKit;
use XML::Parser;

use vars qw($page_id $ATTR_NAME $cur_config
	$global_attr $server_attr $page_attr $uri_match $mtime_hashref);

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

sub get_config_dir {
  my $config = shift;
  return $config->{'config_dir'};
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

  # set global variable so that XML::Parser's handlers can see it
  $cur_config = $config;

  # delete current init
  $uri_match->{$config->{config_dir}} = {};
  $page_attr->{$config->{config_dir}} = {};

  my $p = XML::Parser->new(Style => 'Subs',
			   ParseParamEnt => 1,
			   NoLWP => 1);

  $p->setHandlers(Attlist => \&Attlist);

  $p->parsefile("$config->{config_dir}/Config.xml");
}

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

# used to match pages to regular expressions in the uri_match setting
sub uri_match {
  my ($config, $page_id_in) = @_;
  my $page_id_out;
  while(my ($page_id, $reg_exp) = each %{$uri_match->{$config->{config_dir}}}){
    my $match = '$page_id_in =~ /' . $reg_exp . '/';
    if(eval $match){
      $page_id_out = $page_id;
    }
  }
  return $page_id_out;
}

##################################
# methods for parsing XML file
sub CONFIG {}
sub CONFIG_ {}

# called at <GLOBAL> tag in XML file
sub GLOBAL {
  my ($p, $edtype, %attr) = @_;

  while (my ($key, $value) = each %attr){
    $global_attr->{$cur_config->{config_dir}}->{$key} = $value;
  }
}

sub GLOBAL_ {}
sub SERVERS {}
sub SERVERS_ {}

# called at <SERVER> tag in XML file
sub SERVER {
  my ($p, $edtype, %attr) = @_;

  my $config = $cur_config;
  my $server_id = $attr{id} || 'Default';
  while (my ($key, $value) = each %attr){
    $server_attr->{$config->{config_dir}}->{$server_id}->{$key} = $value;
  }
}

sub SERVER_ {}

sub PAGES {}
sub PAGES_ {}

# called at beginning <PAGE> tag in XML file
sub PAGE {
  my ($p, $edtype, %attr) = @_;

  $page_id = $attr{id};
  my $config = $cur_config;

  while (my ($key, $value) = each %attr){
    next if $key eq 'id';
    if($key eq 'uri_match'){
      $uri_match->{$config->{config_dir}}->{$page_id} = $value;
    } else {
      $page_attr->{$config->{config_dir}}->{$page_id}->{$key} = $value;
    }
  }
}

sub PAGE_ {}

sub Attlist {
  my ($p, $elname, $attname, $type, $default, $fixed) = @_;

  if($elname eq 'GLOBAL' && $default ne '#IMPLIED'){
    $global_attr->{$cur_config->{config_dir}}->{$attname} ||= $default;
  }
}

1;

=head1 NAME

Apache::PageKit::Config - Reads and provides configuration data.

=head1 SYNOPSIS

This is a wrapper class to the global, server and page
configuration settings stored in the
pagekit_root/Config/Config.xml file.

=head1 METHODS

=over 4

=item new

Constructor method, takes configuration directory
and server as arguments.

  my $config = Apache::PageKit::Config->new(config_dir => $config_dir,
					server => $server);

If server is not specified, defaults to 'Default'.

=item parse_xml

Load settings from pagekit_root/Config/Config.xml.

  $config->parse_xml;

=item get_global_attr

  $config->get_global_attr('fill_in_form');

Gets the global fill_in_form attribute.

=item get_server_attr

  $config->get_server_attr('cookie_domain');

Gets the cookie_domain attribute for the server associated with $config.

=item get_page_attr

  $config->get_page_attr($page_id,'use_bread_crumb');

Gets the value of the C<use_bread_crumb> attribute of C<$page_id>.

=back

=head1 CONFIGURATION VARIABLES

=head2 Global Attributes

These settings are global in the sense that they apply over all pages and servers.  They are attributes of the <GLOBAL> tag in Config.xml

=over 4

=item cache_dir

Specifies the directory where the HTML::Template file cache and the
content cache files are stored.  Defaults to C</tmp>.

=item cookies_not_set_page

This is the page that gets displayed if the user attempts to log in,
but their cookies are not enabled.  Defaults to C<login_page>.

=item default_page

Default page user gets when no page is specified.  Defaults to I<index>.

=item login_page

Page that gets displayed when user attempts to log in.  Defaults to I<login>.

=item model_base_class

Specifies the base Model class that typically contains code
that used across entire the web application, including methods for
authentication and connecting to the database.

If you have multiple PageKit applications running on the same mod_perl
server, then you'll need to specify a unique C<model_base_class>
for each application.

Defaults to L<MyPageKit::Common>.

=item model_dispatch_prefix

This prefixes the class that the contains the model code.  Defaults to MyPageKit::MyModel.

Methods in this class take an Apache::PageKit::Model object as their only argument.

=item not_found_page

Error page when page cannot be found.  Defaults to C<default_page>.

=item post_max

Maximum size of file uploads.  Defaults to 100,000,000 (100 MB).

=item recent_login_timeout

Seconds that user's session has to be inactive before a user is asked
to verify a password on pages with the C<require_login> attribute
set to I<recent>.  Defaults to 3600 (1 hour).

=item session_expires

Sets the expire time for the cookie that stores the session id on 
the user's computer.  If it is not set, then the expire time on the
cookie will not be set, and the cookie will expire when the user closes
their browser.

  session = "+3h"

=item uri_prefix

Prefix of URI that should be trimmed before dispatching to the Model code.

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

=item files_match

  files_match = "\.html?$"

Declines requests that match value.

=item html_clean_level

Sets optimization level for L<HTML::Clean>.  If set to 0, disables use of
L<HTML::Clean>.  Levels range from 1 to 9.
Level 1 includes only simple fast optimizations.  Level 9 includes all
optimizations.  Defaults to level 9.

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

=back

=head2 Page Attributes

These options are local to each page on the site, but are global across each server.  The are located in the <PAGES> tag of Config.xml.

=over 4

=item page_id (required)

Page ID for this page.

=item browser_cache

If set to I<no>, sends an Expires = -1 header to disable client-side
caching on the browser.

=item error_page

If a submitted form includes invalid data, then this is the page 
that is displayed.

=item error_page_run_code

If set to I<yes>, then page_code on error_page is run.  Defaults to I<no>.

=item fill_in_form

When set to I<yes>, automatically fills in HTML forms with values from the C<$apr> 
(L<Apache::Request>) object.  If set to I<auto>, fills in HTML forms when it
detects a <form> tag.  Default is I<auto>.

=item internal_title

Title of page displayed on Content Management System. (Forthcoming)

=item new_credential

Should be set to I<yes> for pages that process credentials and update the
database, such as pages that process new registration and forms that set a new login and/or password.

If set to I<yes>, then it reissues the cookie that contains the credentials and
authenticates the user.

=item parent_id

Parent page id - used for navigation bar.

=item request_param_in_tmpl

If set to yes, then <MODEL_VAR> tags in template automatically get filled in
with corresponding request values.  Defaults to no.

=item require_login

If set to I<yes>, page requires a login.  If set to I<recent>, page
requires a login and that the user has been active in the last
C<recent_login_timeout> seconds.  Default is I<no>.

=item template_cache

If set to I<normal>, enables C<cache> option of L<HTML::Template> for the Page and Include templates.

If set to I<shared>, enables C<shared_cache> option of L<HTML::Template>.

=item uri_match

Value should be a regular expression.
Servers requests whose URL (after the host name) match the regular expression.
For example, C<^member\/\d*$> matches http://yourdomain.tld/member/4444.

=item use_bread_crumb

If set to I<yes>, creates bread crumb trail in location specified by
C<E<lt>PKIT_LOOP NAME="BREAD_CRUMB"E<gt> E<lt>/PKIT_LOOPE<gt>> in the template.

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
