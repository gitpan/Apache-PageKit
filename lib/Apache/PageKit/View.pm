package Apache::PageKit::View;

# $Id: View.pm,v 1.38 2001/04/25 15:52:35 tjmather Exp $

# we want to extend this module to use different templating packages -
# Template::ToolKit and HTML::Template

use integer;
use strict;

use File::Find ();
use File::Path ();
use HTML::Clean ();

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
#    * fill_in_template($page_id, $pkit_view, $lang)
#    * open_template($page_id, $pkit_view, $lang)
#    * param
#    * preparse_templates($view_root,$html_clean_level,$view_cache_dir);
#    * template_file_exists($page_id)

# 4. methods that are called interally
#    * _fetch_from_file_cache($page_id, $pkit_view, $lang);
#    * _prepare_content($template_text_ref, $page_id)
#    * _fill_in_content($template_text_ref, $page_id)
#    * _fill_in_content_loop(...)
#    * _load_template($page_id, $pkit_view, [$template_file])

$Apache::PageKit::View::cache_component = {};

sub new($$) {
  my $class = shift;
  my $self = { @_ };
  bless $self, $class;
#  $self->_init(@_);
  return $self;
}

sub fill_in_template {
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
sub open_template {
  my ($view, $page_id, $pkit_view, $lang) = @_;

  return if exists $view->{already_loaded}->{$page_id};

  my $record = $view->_fetch_from_file_cache($page_id, $pkit_view, $lang);
  unless($record){
    # template not cached, load now
    $view->_load_template($page_id, $pkit_view);
    $record = $view->_fetch_from_file_cache($page_id, $pkit_view, $lang);
    die "Error loading record for page_id $page_id and view $pkit_view"
      unless $record;
  }

  if($view->{reload}){
    # check for updated files on disk
    while (my ($filename, $cache_mtime) = each %{$record->{include_mtimes}}){
      my $file_mtime = (stat($filename))[9];
      if($file_mtime != $cache_mtime){
	$record = undef;
	last;
      }
    }
    unless($record){
      # one of the included files changed on disk, reload
      $view->_load_template($page_id, $pkit_view);
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
      ($template_file =~ m!$view_dir/(.*?)/Page/(.*)\.(tmpl|tt)$!);
    return unless $page_id;
    $view->open_template($page_id, $pkit_view);
  };

  File::Find::find($load_template_sub, $view_dir);
}

sub template_file_exists {
  my ($view, $page_id, $pkit_view) = @_;
  my $template_file = "$view->{view_dir}/Default/Page/$page_id.tmpl";
  if(-e "$template_file"){
    return 1;
  } elsif($pkit_view) {
    $template_file = "$view->{view_dir}/$pkit_view/Page/$page_id.tmpl";
    return 1 if (-e "$template_file");
  }
  return 0;
}

# private methods

sub _add_content_mtime {
  my ($view, $content_id) = @_;
  my $filename = $view->{content}->get_filename($content_id);
  return if exists $view->{include_mtimes}->{$filename};
  my $mtime = (stat($filename))[9];
  $view->{include_mtimes}->{$filename} = $mtime;
}

sub _add_parameter {
  my ($view, $param) = @_;
  return unless defined $param;
  push (@{$view->{'pkit_parameters'}},$param)
    unless defined($view->{$param});
}

sub _fetch_from_file_cache {
  my ($view, $page_id, $pkit_view, $lang) = @_;

  my $cache_filename = "$view->{cache_dir}/$page_id.$pkit_view.$lang";

  if(-f "$cache_filename"){
    # cache file exists for specified language
    return Storable::lock_retrieve($cache_filename);
  } else {
    $cache_filename = "$view->{cache_dir}/$page_id.$pkit_view.$view->{default_lang}";
    if(-f "$cache_filename"){
      # cache file exists for default language
      return Storable::lock_retrieve($cache_filename);
    } else {
      return;
    }
  }
}

sub _fill_in_content {
  my ($view, $html_code_ref, $page_id, $lang, $check_for_other_lang) = @_;

  $view->{language_parsed}->{$lang} = 1;

  my $content = $view->{content};

  my $tmpl;
  eval {
    $tmpl = HTML::Template->new(scalarref => $html_code_ref,
				   # don't die when we set a parameter that is not in the template
				   die_on_bad_params=>0,
				   # built in __FIRST__, __LAST__, etc vars
				   loop_context_vars=>1,
				   max_includes => 50);
  };
  if($@){
    die "Can't load template (preprocessing) for $page_id: $@";
  }

  my @params = $tmpl->query;
  for my $name (@params){
    next unless $name =~ m!^pkit_content::!;
    my $type = $tmpl->query(name => $name);
    my ($content_id, $xpath) = (split('::',$name))[1,2];
    $content_id = $page_id if $content_id eq 'pkit_default_source';
    $view->_add_content_mtime($content_id);
    my $value;
    if($type eq 'LOOP'){
      $value = $view->_fill_in_content_loop($html_code_ref, $page_id, $tmpl, $content_id, $lang, [ $name ], $check_for_other_lang);
    } else {
      if($check_for_other_lang){
	my $langs = $content->get_xpath_langs(content_id => $content_id,
					      xpath => $xpath);
	for my $l (@$langs){
	  $view->_fill_in_content($html_code_ref, $page_id, $l, 0)
	    unless exists $view->{language_parsed}->{$l};
	}
      }
      my $nodeset = $content->get_xpath_nodeset(content_id => $content_id,
						xpath => $xpath,
						lang => $lang);

      # get value of first node
      $value = $nodeset->string_value;

      # XML::Parser outputs as utf8, so we convert to latin1 to deal
      # with accented characters in french, german, etc
      if($lang ne 'en' && exists $INC{'Unicode/String.pm'}){
	$value = Unicode::String::utf8($value)->latin1 unless $lang eq 'en';
      }
    }
    $tmpl->param($name => $value);
  }
  # html, filtered for content
  my $filtered_html = $tmpl->output;

  $view->_preparse_model_tags(\$filtered_html);
  $view->_html_clean(\$filtered_html);

  my $filtered_tmpl;
  eval {
    $filtered_tmpl = HTML::Template->new(scalarref => \$filtered_html,
					 # don't die when we set a parameter that is not in the template
					 die_on_bad_params=>0,
					 # built in __FIRST__, __LAST__, etc vars
					 loop_context_vars=>1,
					 max_includes => 50,
					 global_vars=>1);
  };

  if($@){
    die "Can't load template (postprocessing) for $page_id: $@\n------------------TEMPLATE TEXT--------------------------\n\n\n$filtered_html\n\n\n";
  }

  $view->{lang_tmpl}->{$lang} = $filtered_tmpl;
}

sub _fill_in_content_loop {
  my ($view, $html_code_ref, $page_id, $tmpl, $context_content_id, $lang,
      $loops, $check_for_other_lang, $context) = @_;

  my $content = $view->{content};

  my ($xpath) = (split('::',$loops->[-1]))[2];

  my @inner_param_names = $tmpl->query(loop => $loops);
  my %inner_param;
  for my $name (@inner_param_names){
    next unless $name =~ m!^pkit_content::!;
    my ($content_id, $xpath) = (split('::',$name))[1,2];
    if($content_id eq 'pkit_default_source'){
      $content_id = $context_content_id;
#      ($content_id, $xpath) = (split('::',$context_content_id;))[1,2];
    } else {
      $view->_add_content_mtime($content_id);
    }
    $inner_param{$name} = {type => $tmpl->query(name => [ @$loops, $name ]),
			   content_id => $content_id,
			   xpath => $xpath};
    # only use context if in same content_id
    $inner_param{$name}->{use_context} = 1
      if $content_id eq $context_content_id;
  }

  my $nodeset = $content->get_xpath_nodeset(content_id => $context_content_id,
					    xpath => $xpath,
					    lang => $lang,
					    context => $context);

  my $array_ref = [];

  for my $node ($nodeset->get_nodelist){
    my $loop_param = {};
    while (my ($name, $hash_ref) = each %inner_param){
      my $value;
      # only use context if in same content_id
      my $context = (exists $hash_ref->{use_context}) ? $node : undef;
      if($hash_ref->{type} eq 'LOOP'){
	$value = $view->_fill_in_content_loop($html_code_ref, $page_id, $tmpl, $hash_ref->{content_id}, $lang, [ @$loops, $name], $check_for_other_lang, $node);
      } else {
	if($check_for_other_lang){
	  my $langs = $content->get_xpath_langs(content_id => $hash_ref->{content_id},
						xpath => $hash_ref->{xpath},
						context => $context);
	  for my $l (@$langs){
	    $view->_fill_in_content($html_code_ref, $page_id, $l, 0)
	      unless exists $view->{language_parsed}->{$l};
	  }
	}
	my $nodeset = $content->get_xpath_nodeset(content_id => $hash_ref->{content_id},
						  xpath => $hash_ref->{xpath},
						  lang => $lang,
						  context => $context);
	# get value of first node
	$value = $nodeset->string_value;
      }
      $loop_param->{"$name"} = $value;
    }
    push @$array_ref, $loop_param;
  }
  return $array_ref;
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
  my ($view, $html_code_ref, $pkit_view) = @_;

  my %component_ids;

  if($view->{can_edit}){
    if(exists $INC{'Apache/PKCMS/View.pm'}){
      Apache::PKCMS::View::add_component_edit_stubs($html_code_ref);
    }
  }

  $$html_code_ref =~ s/<PKIT_COMPONENT (NAME=)?"?(.*?)"?>/&get_component($2,$view,$pkit_view)/eig;

  my @component_ids = keys %component_ids;
  return \@component_ids;

  sub get_component {
    my ($component_id, $view, $pkit_view) = @_;

    my $template_file = "$view->{view_dir}/$pkit_view/Component/$component_id.tmpl";
    unless(-e "$template_file"){
      $template_file = "$view->{view_dir}/Default/Component/$component_id.tmpl";
      unless (-e "$template_file"){
	die "Cannot find template for component $component_id (view $pkit_view) (looked in $template_file)";
      }
    }

    unless(exists $view->{component_ids_hash}->{$component_id}){
      $view->{component_ids_hash}->{$component_id} = 1;
      push @{$view->{component_ids}}, $component_id;
      my $mtime = (stat(_))[9];
      $view->{include_mtimes}->{$template_file} = $mtime;
    }

    open TEMPLATE, "$template_file";
    local($/) = undef;
    my $template = <TEMPLATE>;
    close TEMPLATE;

    if($view->{can_edit}){
      if(exists $INC{'Apache/PKCMS/View.pm'}){
	Apache::PKCMS::View::add_component_edit_stubs(\$template);
      }
    }

    $template =~ s/<PKIT_COMPONENT (NAME=)?"?(.*?)"?>/&get_component($2, $view, $pkit_view)/eig;
    return $template;
  }
}

sub _load_template {
  my ($view, $page_id, $pkit_view, $template_file) = @_;

  unless($template_file){
    $template_file = "$view->{view_dir}/$pkit_view/Page/$page_id.tmpl";
    unless(-e "$template_file"){
      $template_file = "$view->{view_dir}/Default/Page/$page_id.tmpl";
      unless(-e "$template_file"){
	die "Cannot find template for page_id $page_id";
      }
    }
  }

  open TEMPLATE, "$template_file";
  local($/) = undef;
  my $template = <TEMPLATE>;
  close TEMPLATE;

  my $mtime = (stat "$template_file")[9];

  # include mtimes and component_ids are filled in by _include_components
  # and _fill_in_content
  delete $view->{include_mtimes};
  delete $view->{component_ids};
  delete $view->{component_ids_hash};

  $view->{include_mtimes}->{$template_file} = $mtime;

  $view->_include_components(\$template, $pkit_view);

  $view->_preparse_content_tags(\$template);

#  print $template;

  # setup content object
  $view->{content} ||= Apache::PageKit::Content->new(default_lang => $view->{default_lang},
						     content_dir => $view->{content_dir});

  # fill in content for default lang, 1 at end checks for other languages
  $view->_fill_in_content(\$template, $page_id, $view->{default_lang}, 1);

  # delete languages prepared hash, which is set by _fill_in_content
  delete $view->{language_parsed};

  # go through content files (which have had content filled in)
  while (my ($lang, $tmpl) = each %{$view->{lang_tmpl}}){
    $view->_preparse_model_tags(\$tmpl);
    $view->_html_clean(\$tmpl);
    my $record = {
		  filename => $template_file,
		  html_template => $tmpl,
		  include_mtimes => $view->{include_mtimes},
		  component_ids => $view->{component_ids}
		 };

    # make directories, if approriate
    (my $dir = $page_id) =~ s!(/)?[^/]*?$!!;

    if($dir){
      File::Path::mkpath("$view->{cache_dir}/$dir");
    }

    # Store record
    Storable::lock_store($record, "$view->{cache_dir}/$page_id.$pkit_view.$lang");
  }

  # delete again, just in case...
  delete $view->{lang_tmpl};
  delete $view->{include_mtimes};
  delete $view->{component_ids};
  delete $view->{component_ids_hash};
}

sub _preparse_content_tags {
  my ($view, $html_code_ref) = @_;

  $$html_code_ref =~ s!</CONTENT_(LOOP|IF|UNLESS)>!</TMPL_$1>!sig;

  # break up CONTENT_* tags
  # in general, they are in the form of
  # <CONTENT_VAR SOURCE="content_id" NAME="aaa/bbb">

  $$html_code_ref =~ s!<CONTENT_(VAR|LOOP|IF|UNLESS) # $1
             \s+
      (?:SOURCE\s*=\s*(?:
		"([^">]*)" | # $2
                '([^'>]*)' | # $3
                ([^\s=>]*)   # $4
        )\s+)?
        (?:NAME\s*=\s*(?:
                "([^">]*)" | # $5
		'([^'>]*)' | # $6
                ([^\s=>]*)   # $7
        )\s*)
        (?:SOURCE\s*=\s*(?:
                "([^">]*)" | # $8
                '([^'>]*)' | # $9
	        ([^\s=>]*)   # $10
	        )\s*)?
      >!&tmpl_tag($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)!esigx;

  # pre-process <CONTENT_*> tags in 
  $$html_code_ref =~ s!<CONTENT_(VAR|IF|UNLESS) +NAME *= *("?)__(FIRST|INNER|ODD|LAST)!<TMPL_$1 NAME=$2__$2!sig;
  $$html_code_ref =~ s!<CONTENT_ELSE!<TMPL_ELSE!sig;

  # used for converting <CONTENT_*> tags to <TMPL_*> tags
  sub tmpl_tag {
    my ($a1, $a2, $a3, $a4, $a5, $a6, $a7, $a8, $a9, $a10) = @_;

    my $source = $a2 || $a3 || $a4 || $a8 || $a9 || $a10 || 'pkit_default_source';
    my $name;
    if($a5){
      $name = qq{"pkit_content::${source}::$a5"};
    } elsif($a6) {
      $name = qq{'pkit_content::${source}::$a6'};
    } elsif($a7) {
      $name = qq{pkit_content::${source}::$a7};
    }
    return qq{<TMPL_$a1 NAME=$name>};
  }
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
