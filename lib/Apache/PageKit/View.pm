package Apache::PageKit::View;

# $Id: View.pm,v 1.48 2001/05/07 17:34:59 tjmather Exp $

# we want to extend this module to use different templating packages -
# Template::ToolKit and HTML::Template

use integer;
use strict;

use File::Find ();
use File::Path ();
use HTML::Clean ();

use XML::XPathTemplate ();

use Storable ();

use Carp ();

use Data::Dumper;

# how loading, filter and caching works on the templates.
# 1. templates are pre-filtered, to convert MODEL_*,VIEW_* and PKIT_* tags
# corresponding TMPL_ tags, and to run HTML::Clean

# 2. template objects are loaded and stored on disk or in memory, in
# a hash containing fields from the following set:
#    * html_template - HTML::Template object
#    * template_toolkit - Template-Tookit object
#    * filename - filename of template source
#    * include_mtimes - a hash ref with file names as keys and mtimes as values
#        (contains all of the files included by the <PKIT_COMPONENT> tags
#    * component_ids - an array ref containing component_ids that have
#        code associated with them
# the objects themselves are keyed by page_id, pkit_view and lang

# 3. methods that are called externally
#    * new($view_dir, $content_dir, $cache_dir, $default_lang, $reload, $html_clean_level, $can_edit, [ $associated_objects ], [ $fill_in_form_objects] ) (args passed as hash reference)
#    * fill_in_view($page_id, $pkit_view, $lang)
#    * open_view($page_id, $pkit_view, $lang)
#    * param
#    * preparse_templates($view_root,$html_clean_level,$view_cache_dir);
#    * template_file_exists($page_id)

# 4. methods that are called interally
#    * _fetch_from_file_cache($page_id, $pkit_view, $lang);
#    * _prepare_content($template_text_ref, $page_id)
#    * _fill_in_content($template_text_ref, $page_id)
#    * _fill_in_content_loop(...)
#    * _load_page($page_id, $pkit_view, [$template_file])

$Apache::PageKit::View::cache_component = {};

sub new($$) {
  my $class = shift;
  my $self = { @_ };
  bless $self, $class;
#  $self->_init(@_);
  return $self;
}

sub fill_in_view {
  my ($view) = @_;

  # load record containing HTML::Template object
  my $record = $view->{record};

  my $tmpl = $record->{html_template};

  # fill in data from associated objects (for example from the Apache request
  # object if $apr is set
  foreach my $object (@{$view->{associated_objects}}){
    foreach my $key ($object->param){
      # note that we only fill in MODEL_VARs, to avoid errors when setting
      # loops in HTML::Template
      if ($tmpl->query(name => $key) eq 'VAR'){
	$tmpl->param($key,$object->param($key));
      }
    }
  }

  # finally, we use the $view object to fill in template
  # get params from $view object
  # note that in this case we allow for MODEL_LOOPs as well as MODEL_VARs
  foreach my $key ($view->param){
    my $value = $view->param($key);
    $tmpl->param($key, $value);
  }

  my $output = $tmpl->output;

  # if fill_in_form_objects is set, then we use that to fill in any HTML
  # forms in the template.
  my $fif;
  if(@{$view->{fill_in_form_objects}}){
    $fif = HTML::FillInForm->new();
  }

  foreach my $object (@{$view->{fill_in_form_objects}}){
    $output = $fif->fill(scalarref=>\$output,
			 fobject => $object);
  }

  if(exists $INC{'Apache/PKCMS/View.pm'}){
    Apache::PKCMS::View::add_edit_links($view, $record, \$output);
  }

  return \$output;
}

# opens template, each 
sub open_view {
  my ($view, $page_id, $pkit_view, $lang) = @_;

  return if exists $view->{already_loaded}->{$page_id};

  my $record = $view->_fetch_from_file_cache($page_id, $pkit_view, $lang);
  unless($record){
    # template not cached, load now
    $view->_load_page($page_id, $pkit_view);
    $record = $view->_fetch_from_file_cache($page_id, $pkit_view, $lang);
    die "Error loading record for page_id $page_id and view $pkit_view"
      unless $record;
  }

  if($view->{reload} ne "no"){
    # check for updated files on disk
    unless($view->_is_record_uptodate($record, $pkit_view, $page_id)){
      # one of the included files changed on disk, reload
      $view->_load_page($page_id, $pkit_view);
      $record = $view->_fetch_from_file_cache($page_id, $pkit_view, $lang);
    }
  }

  $view->{record} = $record;
  $view->{already_loaded}->{$page_id} = 1;
}

# param method - can be called in two forms
# when passed two arguments ($name, $value), it sets the value of the 
# $name attributes to $value
# when passwd one argument ($name), retrives the value of the $name attribute
# used to access and set values of <MODEL_*> tags
sub param {
  my ($view, @p) = @_;

  unless(@p){
    # the no-parameter case - return list of parameters
    return () unless defined($view) && $view->{'pkit_parameters'};
    return () unless @{$view->{'pkit_parameters'}};
    return @{$view->{'pkit_parameters'}};
  }
  my ($name, $value);
  # deal with case of setting mul. params with hash ref.
  if (ref($p[0]) eq 'HASH'){
    my $hash_ref = shift(@p);
    push(@p, %$hash_ref);
  }
  if (@p > 1){
    die "param called with odd number of parameters" unless ((@p % 2) == 0);
    while(($name, $value) = splice(@p, 0, 2)){
      $view->_add_parameter($name);
      $view->{pkit_param}->{$name} = $value;
    }
  } else {
    $name = $p[0];
  }
  return $view->{pkit_param}->{$name};
}

sub preparse_templates {
  my ($view) = @_;

  my $view_dir = $view->{view_dir};

  my $load_template_sub = sub {
    return unless /\.tmpl$/;
    my $template_file = "$File::Find::dir/$_";
    my ($pkit_view, $page_id) =
      ($template_file =~ m!$view_dir/([^/]*)/Page/(.*?)\.(tmpl|tt)$!);
    return unless $page_id;
    $view->open_view($page_id, $pkit_view);
  };

  File::Find::find({wanted => $load_template_sub,
		    follow => 1},
		    $view_dir);
}

sub template_file_exists {
  my ($view, $page_id, $pkit_view) = @_;
  return 1 if $view->_find_template($pkit_view,'Page',$page_id);
}

# private methods

sub _add_parameter {
  my ($view, $param) = @_;
  return unless defined $param;
  push (@{$view->{'pkit_parameters'}},$param)
    unless defined($view->{$param});
}

sub _fetch_from_file_cache {
  my ($view, $page_id, $pkit_view, $lang) = @_;

  my ($extra_param, $param_hash);
  if (my @xml_params = sort keys %{$Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id}}){
    my $param_obj = $view->{input_param_obj};
    for my $xml_param (@xml_params){
      $extra_param .= "&$xml_param=" . $param_obj->param($xml_param);
    }
    $param_hash = Digest::MD5->md5_hex($extra_param);
  }

  my $cache_filename = "$view->{cache_dir}/$page_id.$pkit_view.$lang$param_hash";

  if(-f "$cache_filename"){
    # cache file exists for specified language
    return Storable::lock_retrieve($cache_filename);
  } else {
    $cache_filename = "$view->{cache_dir}/$page_id.$pkit_view.$view->{default_lang}$param_hash";
    if(-f "$cache_filename"){
      # cache file exists for default language
      return Storable::lock_retrieve($cache_filename);
    } else {
      return;
    }
  }
}

sub _find_template {
  my ($view, $pkit_view, $type, $id) = @_;
  my $template_file = "$view->{view_dir}/$pkit_view/$type/$id.tmpl";
  if(-e "$template_file"){
    return $template_file;
  } else {
    $template_file = "$view->{view_dir}/Default/$type/$id.tmpl";
    if(-e "$template_file"){
      return $template_file;
    } else {
      return undef;
    }
  }
}

# clean up html, remove white spaces, etc
sub _html_clean {
  my ($view, $html_code_ref) = @_;

  my $html_clean_level = $view->{html_clean_level};

  return unless $html_clean_level > 0;

  my $h = new HTML::Clean($html_code_ref,$Apache::PageKit::View::html_clean_level) || die("can't open HTML::Clean object: $!");
  $h->strip if $Apache::PageKit::View::html_clean_level > 0;
  $$html_code_ref = ${$h->data()};
}

# returns the component_ids included
sub _include_components {
  my ($view, $page_id, $html_code_ref, $pkit_view) = @_;

  $$html_code_ref =~ s/<PKIT_COMPONENT (NAME=)?"?(.*?)"?>/&get_component($2,$view,$pkit_view)/eig;

#  my @component_ids = keys %component_ids;
#  return \@component_ids;

  sub get_component {
    my ($component_id, $view, $pkit_view) = @_;

    # check for recursive pkit_components
    $view->{component_ids_hash}->{$component_id}++;
    if($view->{component_ids_hash}->{$component_id} > 100){
      die "Likely recursive PKIT_COMPONENTS for component_id $component_id and giving up.";
    }

    my $template_ref = $view->_load_component('Component',$page_id,$component_id,$pkit_view);
    return $$template_ref;
  }
}

sub _is_record_uptodate {
  my ($view, $record, $pkit_view, $page_id) = @_;

  # first check timestamps
  my $include_mtimes = $record->{include_mtimes};
  while (my ($filename, $cache_mtime) = each %$include_mtimes){
    # check if file still exists
    unless(-e "$filename"){
      return 0;
    }

    # check if file is up to date
    my $file_mtime = (stat($filename))[9];
#    print "hi $filename - $cache_mtime - $file_mtime<br>";
    if($file_mtime != $cache_mtime){
      return 0;
    }

    if($filename =~ m!^$view->{view_dir}/Default/! && $pkit_view ne 'Default'){
      # check to see if any new files have been uploaded to the $pkit_view dir
      (my $check_filename = $filename)=~ s!^$view->{view_dir}/Default/!$view->{view_dir}/$pkit_view!;
      if (-e "$check_filename"){
	return 0;
      }
    }
  }

  # record up to date!
  return 1;
}

# here the usage of "component" also includes page
sub _load_component {
  my ($view, $type, $page_id, $component_id, $pkit_view) = @_;

  my $template_file = $view->_find_template($pkit_view, $type, $component_id);
  my $template_ref;

  unless($template_file){
    # no template file exists, attempt to generate from XML and XSL files
    # currently only XML::LibXSLT is supported
    $template_ref = $view->{content}->generate_template($type, $page_id, $component_id, $pkit_view, $view->{input_param_obj});
  } else {
    open TEMPLATE, "$template_file";
    local($/) = undef;
    my $template = <TEMPLATE>;
    $template_ref = \$template;
    close TEMPLATE;

    my $mtime = (stat(_))[9];
    $view->{include_mtimes}->{$template_file} = $mtime;
  }

  if($view->{can_edit} eq 'yes'){
    if(exists $INC{'Apache/PKCMS/View.pm'}){
      Apache::PKCMS::View::add_component_edit_stubs($template_ref);
    }
  }

  $view->_include_components($page_id,$template_ref,$pkit_view);

  return $template_ref;
}

sub _load_page {
  my ($view, $page_id, $pkit_view) = @_;

  my $content = $view->{content} ||= Apache::PageKit::Content->new(
						     content_dir => $view->{content_dir},
						     view_dir => $view->{view_dir},
						     default_lang => $view->{default_lang});

  $view->{lang_tmpl} = $content->{lang_tmpl} = {};
  $view->{include_mtimes} = $content->{include_mtimes} = {};
  $view->{component_ids_hash} = {};

  my $template_file = $view->_find_template($pkit_view, 'Page', $page_id);
  my $template_ref = $view->_load_component('Page',$page_id,$page_id,$pkit_view);

#  my $template_file = $view->_find_template($pkit_view, 'Page', $page_id);
  my $lang_tmpl = $content->process_template($page_id, $template_ref);

  # go through content files (which have had content filled in)
  while (my ($lang, $filtered_html) = each %$lang_tmpl){
    $view->_preparse_model_tags($filtered_html);
    $view->_html_clean($filtered_html);

    my $tmpl;
    eval {
      $tmpl = HTML::Template->new(scalarref => $filtered_html,
					   # don't die when we set a parameter that is not in the template
					   die_on_bad_params=>0,
					   # built in __FIRST__, __LAST__, etc vars
					   loop_context_vars=>1,
					   max_includes => 50,
					   global_vars=>1);
    };
    if($@){
      die "Can't load template (postprocessing) for $page_id: $@"
    }
    my @component_ids = keys %{$view->{component_ids_hash}};
    my $record = {
		  filename => $template_file,
		  html_template => $tmpl,
		  include_mtimes => $view->{include_mtimes},
		  component_ids => \@component_ids
		 };

    # make directories, if approriate
    (my $dir = $page_id) =~ s!(/)?[^/]*?$!!;

    if($dir){
      File::Path::mkpath("$view->{cache_dir}/$dir");
    }

    my ($extra_param, $param_hash);
    if (my @xml_params = sort keys %{$Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id}}){
      my $param_obj = $view->{input_param_obj};
      for my $xml_param (@xml_params){
	$extra_param .= "&$xml_param=" . $param_obj->param($xml_param);
      }
      $param_hash = Digest::MD5->md5_hex($extra_param);
    }

    # Store record
    Storable::lock_store($record, "$view->{cache_dir}/$page_id.$pkit_view.$lang$param_hash");
  }

  # include mtimes and component_ids are filled in by _include_components
  # and _fill_in_content
  delete $view->{include_mtimes};
  delete $view->{lang_tmpl};
  delete $view->{component_ids_hash};
}

sub _preparse_model_tags {
  my ($view, $html_code_ref) = @_;

  # "compile" PageKit templates into HTML::Templates
  $$html_code_ref =~ s!<MODEL_(VAR|LOOP|IF|ELSE|UNLESS)!<TMPL_$1!sig;
  $$html_code_ref =~ s!</MODEL_(LOOP|IF|UNLESS)!</TMPL_$1!sig;

  $$html_code_ref =~ s!<PKIT_ERRORFONT (NAME=)?"?([^"]*?)"?>(.*?)</PKIT_ERRORFONT>!<TMPL_VAR NAME="PKIT_ERRORFONT_BEGIN_$2">$3<TMPL_VAR NAME="PKIT_ERRORFONT_END_$2">!sig;
  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)__(FIRST|INNER|ODD|LAST)!<TMPL_$1 NAME=$2__$3!sig;
  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)!<TMPL_$1 NAME=$2PKIT_!sig;
  $$html_code_ref =~ s!<PKIT_ELSE!<TMPL_ELSE!sig;
  $$html_code_ref =~ s!</PKIT_(LOOP|IF|UNLESS)!</TMPL_$1!sig;
}

1;
__END__

=head1 NAME

Apache::PageKit::View - Bridge between Apache::PageKit and HTML::Template

=head1 SYNOPSIS

This class is a wrapper class to HTML::Template.  It simplifies the calls to 
output a new template, and
fills in CGI forms using L<HTML::FillInForm> and resolves <MODEL_*>,
<CONTENT_*> and <PKIT_*> tags.

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
