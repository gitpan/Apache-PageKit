package Apache::PageKit::View;

# $Id: View.pm,v 1.54 2001/05/19 22:20:36 tjmather Exp $

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
#    * exclude_params - array ref of lists of params to be excluded from <PKIT_SELFURL> tags
#    * html_template - HTML::Template object
#    * template_toolkit - Template-Tookit object
#    * filename - filename of template source
#    * include_mtimes - a hash ref with file names as keys and mtimes as values
#        (contains all of the files included by the <PKIT_COMPONENT> tags
#    * component_ids - an array ref containing component_ids that have
#        code associated with them
#    * has_form - 1 if contains <form> tag, 0 otherwise.  used to
#        determine whether to apply HTML::FillInForm module
# the objects themselves are keyed by page_id, pkit_view and lang

# 3. methods that are called externally
#    * new($view_dir, $content_dir, $cache_dir, $default_lang, $reload, $html_clean_level, $can_edit, [ $associated_objects ], [ $fillinform_objects], $input_param_object, $output_param_object) (args passed as hash reference)
#    * fill_in_view($page_id, $pkit_view, $lang)
#    * open_view($page_id, $pkit_view, $lang)
#    * param
#    * preparse_templates($view_root,$html_clean_level,$view_cache_dir);
#    * template_file_exists($page_id, $pkit_view)

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

  # Fill in (compiled) <PKIT_SELFURL> tags
  my $exclude_params_set = $record->{exclude_params_set};
  if($exclude_params_set && @$exclude_params_set){
    my $input_param_object = $view->{input_param_object};
    my $orig_uri = $input_param_object->notes('orig_uri');
    foreach my $exclude_params (@$exclude_params_set){
      my @exclude_params = split(" ",$exclude_params);
      my $query_string = Apache::PageKit::params_as_string($input_param_object, \@exclude_params);
      if($query_string){
	$tmpl->param("pkit_selfurl$exclude_params", ($orig_uri . '?' . $query_string) . '&');
      } else {
	$tmpl->param("pkit_selfurl$exclude_params", $orig_uri . '?');
      }
    }
  }
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

  # finally, we use the $output_param_object object to fill in template
  # get params from $view object
  # note that in this case we allow for MODEL_LOOPs as well as MODEL_VARs
  my $output_param_object = $view->{output_param_object};
  foreach my $key ($output_param_object->param){
    my $value = $output_param_object->param($key);
    $tmpl->param($key, $value);
  }

  my $output = $tmpl->output;

  if($record->{has_form}){
    # if fillinform_objects is set, then we use that to fill in any HTML
    # forms in the template.
    my $fif;
    if(@{$view->{fillinform_objects}}){
      $fif = HTML::FillInForm->new();
      $output = $fif->fill(scalarref=>\$output,
			   fobject => $view->{fillinform_objects} );
    }
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

  File::Find::find({wanted => $load_template_sub},
#		    follow => 1},
		    $view_dir);
}

sub template_file_exists {
  my ($view, $page_id, $pkit_view) = @_;
  return 1 if $view->_find_template($pkit_view,$page_id);
}

# private methods

sub _fetch_from_file_cache {
  my ($view, $page_id, $pkit_view, $lang) = @_;

  my ($extra_param, $param_hash) = ("","");
  if (my @xml_params = sort keys %{$Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id}}){
    my $param_obj = $view->{input_param_object};
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
  my ($view, $pkit_view, $id) = @_;
  my $template_file = "$view->{view_dir}/$pkit_view/$id.tmpl";
  if(-e "$template_file"){
    return $template_file;
  } else {
    $template_file = "$view->{view_dir}/Default/$id.tmpl";
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

  my $h = new HTML::Clean($html_code_ref,$html_clean_level) || die("can't open HTML::Clean object: $!");
  $h->strip if $html_clean_level > 0;
  $$html_code_ref = ${$h->data()};
}

# returns the component_ids included
sub _include_components {
  my ($view, $page_id, $html_code_ref, $pkit_view) = @_;

  $$html_code_ref =~ s!<PKIT_COMPONENT (NAME=)?"?(.*?)"?>(</PKIT_COMPONENT>)?!&get_component($page_id,$2,$view,$pkit_view)!eig;

#  my @component_ids = keys %component_ids;
#  return \@component_ids;

  sub get_component {
    my ($page_id,$component_id, $view, $pkit_view) = @_;

    unless($component_id =~ s!^/!!){
      # relative component, component relative to page_id
      (my $page_id_dir = $page_id) =~ s![^/]*$!!;
      $component_id = $page_id_dir . $component_id;
      while ($component_id =~ s![^/]*/\.\./!!) {};
    }

    # check for recursive pkit_components
    $view->{component_ids_hash}->{$component_id}++;
    if($view->{component_ids_hash}->{$component_id} > 100){
      die "Likely recursive PKIT_COMPONENTS for component_id $component_id and giving up.";
    }

    my $template_ref = $view->_load_component($page_id,$component_id,$pkit_view);
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
      (my $check_filename = $filename) =~ s!^$view->{view_dir}/Default/!$view->{view_dir}/$pkit_view/!;
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
  my ($view, $page_id, $component_id, $pkit_view) = @_;

  my $template_file = $view->_find_template($pkit_view, $component_id);
  my $template_ref;

  unless($template_file){
    # no template file exists, attempt to generate from XML and XSL files
    # currently only XML::LibXSLT is supported
    $template_ref = $view->{content}->generate_template($page_id, $component_id, $pkit_view, $view->{input_param_object});
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

  my $template_file = $view->_find_template($pkit_view, $page_id);
  my $template_ref = $view->_load_component($page_id,$page_id,$pkit_view);

#  my $template_file = $view->_find_template($pkit_view, $page_id);
  my $lang_tmpl = $content->process_template($page_id, $template_ref);

  # go through content files (which have had content filled in)
  while (my ($lang, $filtered_html) = each %$lang_tmpl){
    my $exclude_params_set = $view->_preparse_model_tags($filtered_html);
    $view->_html_clean($filtered_html);

    my $has_form = ($$filtered_html =~ m!<form!i);

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
		  exclude_params_set => $exclude_params_set,
		  filename => $template_file,
		  html_template => $tmpl,
		  include_mtimes => $view->{include_mtimes},
		  component_ids => \@component_ids,
		  has_form => $has_form
		 };

    # make directories, if approriate
    (my $dir = $page_id) =~ s!(/)?[^/]*?$!!;

    if($dir){
      File::Path::mkpath("$view->{cache_dir}/$dir");
    }

    my ($extra_param, $param_hash) = ("", "");
    if (my @xml_params = sort keys %{$Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id}}){
      my $param_obj = $view->{input_param_object};
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

  my $exclude_params_set = {};

  # "compile" PageKit templates into HTML::Templates
  $$html_code_ref =~ s!<MODEL_(VAR|LOOP|IF|ELSE|UNLESS)!<TMPL_$1!sig;
  $$html_code_ref =~ s!</MODEL_(LOOP|IF|UNLESS)!</TMPL_$1!sig;

  # tags generated by XSLT
  $$html_code_ref =~ s!</(MODEL|PKIT)_VAR>!!ig;

  $$html_code_ref =~ s!<PKIT_SELFURL( +exclude=('|")(.*?)('|"))? *>!&process_selfurl_tag($exclude_params_set, $3)!eig;

  $$html_code_ref =~ s!<PKIT_ERRORFONT (NAME=)?"?([^"]*?)"?>(.*?)</PKIT_ERRORFONT>!<TMPL_VAR NAME="PKIT_ERRORFONT_BEGIN_$2">$3<TMPL_VAR NAME="PKIT_ERRORFONT_END_$2">!sig;
  $$html_code_ref =~ s!<PKIT_HOSTNAME>!<TMPL_VAR NAME="PKIT_HOSTNAME">!ig;

  $$html_code_ref =~ s!<PKIT_MESSAGES>!<TMPL_LOOP NAME="PKIT_MESSAGES">!ig;
  $$html_code_ref =~ s!<PKIT_IS_ERROR>!<TMPL_IF NAME="PKIT_IS_ERROR">!ig;
  $$html_code_ref =~ s!</PKIT_IS_ERROR>!</TMPL_IF>!ig;
  $$html_code_ref =~ s!<PKIT_MESSAGE>!<TMPL_VAR NAME="PKIT_MESSAGE">!ig;
  $$html_code_ref =~ s!</PKIT_MESSAGES>!</TMPL_LOOP>!ig;

  $$html_code_ref =~ s!<PKIT_VIEW +NAME *= *('|")?(.*?)('|")? *>!<TMPL_IF NAME="PKIT_VIEW:$2">!sig;
  $$html_code_ref =~ s!</PKIT_VIEW>!</TMPL_IF>!ig;

  if($$html_code_ref =~ m!<PKIT_(VAR|LOOP|IF|UNLESS) (.*?)>!){
    warn "PKIT_VAR, PKIT_LOOP, PKIT_IF, and PKIT_UNLESS are depreciated.  use PKIT_HOSTNAME, PKIT_VIEW, PKIT_MESSAGES, PKIT_IS_ERROR, or PKIT_MESSAGE instead";
  }

#  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)__(FIRST|INNER|ODD|LAST)!<TMPL_$1 NAME=$2__$3!sig;
#  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)!<TMPL_$1 NAME=$2PKIT_!sig;
  $$html_code_ref =~ s!<PKIT_ELSE!<TMPL_ELSE!sig;
  $$html_code_ref =~ s!</PKIT_(LOOP|IF|UNLESS)!</TMPL_$1!sig;

  my @a = keys %$exclude_params_set;
  return \@a;

  sub process_selfurl_tag {
    my ($exclude_params_set, $exclude_params) = @_;
    $exclude_params = defined($exclude_params) ? 
      join(" ",sort split(/\s+/,$exclude_params)) : "";
    %$exclude_params_set->{$exclude_params} = 1;
    return qq{<TMPL_VAR NAME="pkit_selfurl$exclude_params">};
  }
}

1;
