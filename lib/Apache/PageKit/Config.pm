package Apache::PageKit::Config;

# $Id: Config.pm,v 1.24 2001/08/12 21:34:18 borisz Exp $

use integer;
use strict;
use Apache::PageKit;
use XML::Parser;

use vars qw($page_id $ATTR_NAME $cur_config
	$global_attr $server_attr $view_attr $page_attr $uri_match $mtime_hashref);

sub new {
  my $class = shift;
  my $self = { @_ };
  unless (-d "$self->{'config_dir'}"){
    die "Config directory $self->{'config_dir'} doesn't exist";
  }
  if($self->{'config_dir'} =~ m!/$!){
    warn "Config directory $self->{'config_dir'} has trailing slash";
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

sub get_view_attr {
  my ($config, $view_id, $key) = @_;
  return $view_attr->{$config->{config_dir}}->{$view_id}->{$key};
}

# required page_id paramater
sub get_page_attr {
  my ($config, $page_id, $key) = @_;

  return unless exists $page_attr->{$config->{config_dir}}->{$page_id};
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
      last;
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

sub VIEWS {}
sub VIEWS_ {}

# called at <VIEW> tag in XML file
sub VIEW {
  my ($p, $edtype, %attr) = @_;

  my $config = $cur_config;
  my $view_id = $attr{id} || 'Default';
  while (my ($key, $value) = each %attr){
    $view_attr->{$config->{config_dir}}->{$view_id}->{$key} = $value;
  }
}

sub VIEW_ {}

sub PAGES {}
sub PAGES_ {}

# called at beginning <PAGE> tag in XML file
sub PAGE {
  my ($p, $edtype, %attr) = @_;

  my $page_id = $attr{id};
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
