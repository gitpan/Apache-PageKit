package Apache::PageKit::View;

# $Id: View.pm,v 1.19 2001/01/16 07:27:51 tjmather Exp $

use integer;
use strict;

use File::Find ();
use HTML::Clean ();

# stores components that are cached so we can we can pass cached=>1 to HTML::Template
$Apache::PageKit::View::cache_component = {};

sub new($$) {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  $self->_init(@_);
  return $self;
}

#class method to clean, pre-parse templates
sub preparse_templates {
  my ($class, $template_root, $html_clean_level, $cache_dir) = @_;

  # set to global variable so it is seen when called back
  # from HTML::Template
  $Apache::PageKit::View::html_clean_level = $html_clean_level;

  File::Find::find(
		   sub {
		     return unless /\.tmpl$/;
		     HTML::Template->new(
					 filename => "$File::Find::dir/$_",
					 file_cache => 1,
					 file_cache_dir => "$cache_dir",
					 file_cache_dir_mode => 0755,
					 filter => \&preparse_filter
					);
		   },
		   $template_root
		  );
}

# subroutine that is passed to HTML::Template and
# is used to convert <MODEL_*> <CONTENT_*> tags
# to <TMPL_VAR_*> tags and to optimize the HTML
# using HTML::Clean
sub preparse_filter {
  my $html_code_ref = shift;

  my $h = new HTML::Clean($html_code_ref,$Apache::PageKit::View::html_clean_level) || die("can't open HTML::Clean object: $!");
  $h->strip;
  $$html_code_ref = ${$h->data()};

  # "compile" PageKit templates into HTML::Templates
  $$html_code_ref =~ s!<MODEL_(VAR|LOOP|IF|ELSE|UNLESS)!<TMPL_$1!sig;
  $$html_code_ref =~ s!</MODEL_(LOOP|IF|UNLESS)!</TMPL_$1!sig;
  $$html_code_ref =~ s!<PKIT_ERRORFONT (NAME=)?"?([^"]*?)"?>(.*?)</PKIT_ERRORFONT>!<TMPL_VAR NAME="PKIT_ERRORFONT_BEGIN_$2">$3<TMPL_VAR NAME="PKIT_ERRORFONT_END_$2">!sig;
  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)__(FIRST|INNER|ODD|LAST)!<TMPL_$1 NAME=$2__$3!sig;
  $$html_code_ref =~ s!<PKIT_(VAR|LOOP|IF|UNLESS) +NAME *= *("?)!<TMPL_$1 NAME=$2PKIT_!sig;
  $$html_code_ref =~ s!<PKIT_ELSE!<TMPL_ELSE!sig;
  $$html_code_ref =~ s!</PKIT_(LOOP|IF|UNLESS)!</TMPL_$1!sig;
  $$html_code_ref =~ s!<CONTENT_(VAR|LOOP) +NAME *= *("?)__(FIRST|INNER|ODD|LAST)!<TMPL_$1 NAME=$2__$2!sig;
  $$html_code_ref =~ s!<CONTENT_(VAR|LOOP) +NAME *= *("?)!<TMPL_$1 NAME=$2content:!sig;
  $$html_code_ref =~ s!</CONTENT_LOOP>!</TMPL_LOOP>!sig;
}

sub _init {
  my ($view, $pk) = @_;

  # bad to contain $pk, should try to change later...
  $view->{pk} = $pk;

  my $apr = $pk->{apr};
  my $model = $pk->{model};
  my $session = $pk->{session};
  my $config = $pk->{config};
  my $cache_dir = $config->get_global_attr('cache_dir') . '/pagekit_view_cache';

  $view->{template_root} = $apr->dir_config('PKIT_ROOT') . "/View";

  $view->{templateOptions} = {
			      # don't die when we set a parameter that is not in the template
			      die_on_bad_params=>0,
			      # built in __FIRST__, __LAST__, etc vars
			      loop_context_vars=>1,
			      file_cache_dir => $cache_dir,
			      filter => \&preparse_filter,
			      global_vars=>1,
			     };

  # get Locale settings
  my @accept_language = map {substr($_,0,2) } split(", ",$apr->header_in('Accept-Language'));

  if(my $lang = $apr->param('pkit_lang')){
    $session->{'pkit_lang'} = $lang;
    unshift @accept_language, $lang;
  } elsif ($session){
    unshift @accept_language, $session->{'pkit_lang'} if exists $session->{'pkit_lang'};
  }

  $view->{lang} = [ @accept_language ];
}

sub prepare_component {
  my ($view, $component_id) = @_;
  my $pk = $view->{pk};
  my $config = $pk->{config};

  $pk->component_code($component_id);

  my $template_name = "/Component/" . $component_id;

  my $options = {};
  my $template_cache = $config->get_page_attr($pk->{page_id},'template_cache');
  if($template_cache eq 'yes'){
    $options->{double_file_cache} = 1;
    $Apache::PageKit::View::cache_component->{$component_id} = 'yes';
  } elsif ($Apache::PageKit::View::cache_component->{$component_id} eq 'yes'){
    $options->{double_file_cache} = 1;
  } else {
    $options->{file_cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);
  return $output;
}

sub template_file_exists {
  my ($view, $page_id) = @_;
  my $template_file = $view->{template_root} . "/Default/Page/" . $page_id . '.tmpl';
  return 1 if (-e "$template_file");
  my $pkit_view = $view->{pk}->{apr}->param('pkit_view'); 
  $template_file = $view->{template_root} . "/$pkit_view/Page/" . $page_id . '.tmpl';
  return 1 if (-e "$template_file"); 
  return 0;
}

sub prepare_output {
  my $view = shift;
  my $pk = $view->{pk};
  my $config = $pk->{config};
  my $apr = $pk->{apr};
  my $model = $pk->{model};

  my $page_id = $pk->{page_id};

  my $template_name = "/Page/" . $page_id;

  my $options = {};
  my $template_cache = $config->get_page_attr($pk->{page_id},'template_cache');
  if($template_cache eq 'yes'){
    $options->{double_file_cache} = 1;
  } else {
    $options->{file_cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);

  my @params = $apr->param;

  # make html forms "sticky"
  my $fill_in_form = $config->get_page_attr($pk->{page_id},'fill_in_form');

  # here we call HTML::FillInForm if fill_in_form=yes
  # or fill_in_form=auto and output contains form tag
  if ($fill_in_form eq 'yes' ||
	($fill_in_form ne 'no' && @params && $output =~ m/<form/i)){
    $view->{fif} ||= HTML::FillInForm->new();
    $output = $view->{fif}->fill(scalarref=>\$output,
				    fobject=>$apr);
  }

  $view->{output} = \$output;
}

# common code for page, view and component templates
sub prepare_template {
  my $view = shift;
  my $template_name = shift;
  my $options = shift;

  my $pk = $view->{pk};

  my $filename;
  my $pkit_view = $pk->{apr}->param('pkit_view');
  if ($pkit_view && -e "$view->{template_root}/$pkit_view/$template_name.tmpl"){
    $filename = "$view->{template_root}/$pkit_view/$template_name.tmpl";
  } elsif (-e "$view->{template_root}/Default/$template_name.tmpl") {
    $filename = "$view->{template_root}/Default/$template_name.tmpl";
  } else {
    return "Error could not locate $view->{template_root}/Default/$template_name.tmpl";
  }

  my $template = HTML::Template->new_file($filename,
					  %{$view->{templateOptions}},
					  %$options);

  $view->_apply_param($template);

  my $output = "";

#  if($view->param('pkit_admin')){
#    # add edit link for pkit_admins
#
#    $template_name =~ s!^/!!;
#
#    my $pkit_done = Apache::Util::escape_uri($view->param('pkit_done'));
#
#    $output = qq{<font size="-1"><a href="/pkit_edit/open_view?template=$template_name&pkit_done=$pkit_done">(edit template $template_name)</a></font>};
#  }

  $output .= $template->output;

  $output =~ s/<PKIT_COMPONENT (NAME=)?"?(.*?)"?>/$view->prepare_component($2)/eig;

  return $output;
}

sub _apply_param {
  my ($view, $template) = @_;

  my $pk = $view->{pk};
  my $model = $pk->{model};
  my $config = $pk->{config};

  my $page_id = $pk->{page_id};

  # get params from XML file
  my $param_hashref = $pk->{content}->get_param_hashref($page_id);
  while (my ($key, $value) = each %$param_hashref){
    $template->param($key,$value);
  }

  # get params from GET/POST request
  # so programmer doesn't have to manually put them in the view object
  if($config->get_global_attr('request_param_in_tmpl') eq 'yes'){
    foreach my $key ($pk->{apr}->param){
      $template->param($key,$pk->{apr}->param($key))
        if $template->query(name => $key) eq 'VAR';
    }
  }

  # get params from $view object
  foreach my $key ($view->param){
    my $value = $view->param($key);
    unless (ref($value) eq 'ARRAY' && $template->query(name => $key) ne 'LOOP'){
      $template->param($key, $value);
    } else {
      # avoid attemt a scalar parameter  with an array ref - parameter is not a TMPL_LOOP!
      # error in HTML::Template
      $template->param($key, scalar @$value);
    }
  }
}

sub output_ref {
  my $view = shift;

  return $view->{output};
}

sub get_template_root {
  my $view = shift;
  return $view->{template_root};
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

sub _add_parameter {
  my ($view, $param) = @_;
  return unless defined $param;
  push (@{$view->{'pkit_parameters'}},$param)
    unless defined($view->{$param});
}

1;

__END__

=head1 NAME

Apache::PageKit::View - Bridge between Apache::PageKit and HTML::Template

=head1 SYNOPSIS

This class is a wrapper class to HTML::Template.  It simplifies the calls to 
output a new templat, and
fills in CGI forms using L<HTML::FillInForm> and resolves <MODEL_*>,
<CONTENT_*> and <PKIT_*> tags.

=head1 METHODS

The following methods are available to the user as Apache::PageKit::View API.

=over 4

=item new

  my $view = new Apache::PageKit::View;

Constructor for new object.

=item prepare_component

  $view->prepare_component(34);

Calles the code for the component with id 34 and fills in the component template.

=item prepare_output

Resolves C<E<lt>PKIT_*E<gt>> tags and fills in HTML forms using L<HTML::FillInForm>.

=item output_ref

Returns a reference to the output of the parsed template.

=back

=head1 SEE ALSO

L<Apache::PageKit>, L<HTML::FillInForm>, L<HTML::Template>

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
