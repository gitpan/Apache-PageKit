package Apache::PageKit::View;

# $Id: View.pm,v 1.1 2000/08/29 19:01:11 tjmather Exp $

use integer;
use strict;

# stores modules that are cached so we can we can pass cached=>1 to HTML::Template
$Apache::PageKit::View::cache_module = {};

sub new($$) {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  $self->_init(@_);
  return $self;
}

sub _init {
  my ($view, $pk) = @_;
  $view->{pk} = $pk;

  $view->{template_root} = $pk->{apr}->dir_config('PKIT_TEMPLATE_ROOT') || $pk->{apr}->document_root;

  $view->{templateOptions} = {
			      # don't die when we set a parameter that is not in the template
			      die_on_bad_params=>0,
			      # built in __FIRST__, __LAST__, etc vars
			      loop_context_vars=>1,
			      global_vars=>1,
			     };
}

sub prepare_module {
  my ($view, $module_id) = shift;
  my $pk = $view->{pk};
  my $info = $pk->{info};

  $pk->module_code($module_id);

  my $template_name = "/Module/" . $module_id;

  my $options = {};
  my $template_cache = $info->get_attr('template_cache');
  if($template_cache eq 'shared'){
    $options->{shared_cache} = 1;
  } elsif ($template_cache eq 'normal'){
    $options->{cache} = 1;
    $Apache::PageKit::View::cache_module->{$module_id} = 1;
  } elsif (exists $Apache::PageKit::View::cache_module->{$module_id}){
    $options->{cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);
  $view->param("PKIT_MODULE:$module_id" => $output);
}

sub prepare_page {
  my $view = shift;
  my $pk = $view->{pk};
  my $info = $pk->{info};

  my $page_id = $pk->{page_id};

  my $template_name = "/Page/" . $page_id;

  my $options = {};
  my $template_cache = $info->get_attr('template_cache');
  if($template_cache eq 'shared'){
    $options->{shared_cache} = 1;
  } elsif ($template_cache eq 'normal'){
    $options->{cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);
  $view->param(PKIT_PAGE => $output);
}

sub prepare_template {
  my $view = shift;
  my $template_name = shift;
  my $options = shift;

  my $pk = $view->{pk};

  my $filename;
  if(my $pkit_view = $pk->{apr}->param('pkit_view')){
    if(-e "$view->{template_root}$template_name.$pkit_view.tmpl"){
      $filename = "$view->{template_root}$template_name.$pkit_view.tmpl";
    } else {
      $filename = "$view->{template_root}$template_name.tmpl";
    }
  } else {
    $filename = "$view->{template_root}$template_name.tmpl";
  }

  if($view->param('pkit_admin')){
    # add edit link for pkit_admins
    my $array_ref = $view->param('pkit_edit');
    my ($template_id) = ($template_name =~ m(^/(.*).tmpl$));
    push @$array_ref, {template => $template_id};

    # also add links for TMPL_INCLUDES
    open TEMPLATE, $filename;
    local $/ = undef;
    my $template = <TEMPLATE>;
    close TEMPLATE;

    my $pkit_done = $view->param("pkit_done");

    while ($template =~ m(<TMPL_INCLUDE NAME="\.\./(.*?)\.tmpl">)g){
      push @$array_ref, {template => $1};
    }
    $view->param('pkit_edit',$array_ref);
  }

  my $template = HTML::Template->new_file($filename,
					  %{$view->{templateOptions}},
					  %$options);

  my @modules = map { m/^PKIT_MODULE:(.*?)$/ } $template->param;

  for (@modules){
    $view->prepare_module($_);
  }
  $view->_apply_param($template);
  return $template->output;
}

sub _apply_param {
  my ($view, $template) = @_;

  my $pk = $view->{pk};

  my $page_id = $pk->{page_id};

  # get params from XML file
  my $param_hashref = $pk->{info}->get_param_hashref;
  while (my ($key, $value) = each %$param_hashref){
    $template->param($key,$value);
#      if $template->query(name => $key) eq 'VAR';
  }
  foreach my $key ($view->{pk}->{apr}->param){
    $template->param($key,$pk->{apr}->param($key))
      if $template->query(name => $key) eq 'VAR';
  }
  foreach my $key ($view->param){
    $template->param($key,$view->param($key));
  }
}

# prepare whole page
sub prepare_entire_page {
  my ($view) = @_;
  my $pk = $view->{pk};
  my $apr = $pk->{apr};
  my $info = $pk->{info};

  my $page_view = $info->get_attr('view');

  my $template_name = "/View/" . $page_view;

  my $options = {};
  if($pk->{view_cache} eq 'shared'){
    $options->{shared_cache} = 1;
  } elsif ($pk->{view_cache} eq 'normal'){
    $options->{cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);

  # put something in $html

#  return $$html;

  if ($apr->dir_config('PKIT_PRODUCTION') eq 'on'){
#    $output =~ s/<!--.*?-->//sg;
#    $output =~ s/[ \t]+/ /g;
  }

  my $pkit_link_ref = sub {
    my ($page_id, $query_string) = @_;

    my $protocal = ($info->get_attr('is_secure',$page_id) eq 'yes') ? 'https://' : 'http://';

    if($info->get_attr('is_popup',$page_id) eq 'yes'){
      $view->param(java_script_code => 1);
      my $domain = (split(':',$apr->headers_in->{'Host'}))[0];
      my $popup_height = $info->get_attr('popup_height',$page_id);
      my $popup_width = $info->get_attr('popup_width',$page_id);
      return qq{<a href="javascript:openWindow('http://} . $domain . qq{/} . $page_id . $query_string . qq{',$popup_width,$popup_height)">};
    } elsif ($apr->dir_config('PKIT_PAGE_DOMAIN') eq 'on' && (my $domain = $info->get_attr('domain',$page_id))){
      return qq{<a href="$protocal$domain/$page_id$query_string">};
    } else {
      return qq{<a href="/$page_id$query_string">};
    }
  };

  $output =~ s/<PKIT_LINK (PAGE=)?"?(.*?)(\?[^"]*?)?"?>/&$pkit_link_ref($2, $3)/eig;
  $output =~ s/<\/PKIT_LINK>/<\/a>/ig;

  my @params = $apr->param;

  if($view->param('java_script_code')){
    # add javascipt code
    my $java_script_code = <<END;
<script language="JavaScript">
<!--
var remote=null;
function rs(n,u,w,h,x) {
        args="width="+w+",height="+h+",resizable=yes,scrollbars=no,status=0";
        remote=window.open(u,n,args);
        if (remote != null) {
                if (remote.opener == null)
                        remote.opener = self;
        }
        if (x == 1) { return remote; }
}
function openWindow(url, width, height) {
        awnd=rs('pagekit_popup',url,width,height,1);
        awnd.focus();
}
// -->
</script>
END
    $output =~ s/<PKIT_JAVASCRIPT>/$java_script_code/ig;
  } else {
    # for mod_perl <= 1.24 need to have to global substitution b/c of bug in mod_perl
    $output =~ s/<PKIT_JAVASCRIPT>//ig;
  }

  my $pkit_errorfont_ref = sub {
    my ($name, $text) = @_;
    my $validator = $pk->{validator};
    if($validator && $validator->is_error_field($name)){
      return qq{<font color="#ff000">$text</font>};
    } else {
      return $text;
    }
  };

  $output =~ s/<PKIT_ERRORFONT (NAME=)?"?([^"]*?)"?>(.*?)<\/PKIT_ERRORFONT>/&$pkit_errorfont_ref($2,$3)/egs;

  # make html forms "sticky"
  if ($pk->{fill_in_form} && @params && $output =~ m/<form/i){
    $view->{fif} ||= HTML::FillInForm->new();
    $output = $view->{fif}->fill(scalarref=>\$output,
				    fobject=>$apr);
  }

  $view->{output} = \$output;
}

# param method - can be called in two forms
# when passed two arguments ($name, $value), it sets the value of the 
# $name attributes to $value
# when passwd one argument ($name), retrives the value of the $name attribute
sub param {
  my ($view, @p) = @_;

  unless(@p){
    # the no-parameter case - return list of parameters
    return () unless defined($view) && $view->{'.parameters'};
    return () unless @{$view->{'.parameters'}};
    return @{$view->{'.parameters'}};
  }
  my ($name, $value);
  if (@p > 1){
    die "param called with odd number of parameters" unless ((@p % 2) == 0);
    while(($name, $value) = splice(@p, 0, 2)){
      $view->_add_parameter($name);
      $view->{param}->{$name} = $value;
      if ($name eq 'boardID'){
	warn "$name -> $value";
      }
    }
  } else {
    $name = $p[0];
  }
  return $view->{param}->{$name};
}

sub _add_parameter {
  my ($view, $param) = @_;
  return unless defined $param;
  push (@{$view->{'.parameters'}},$param)
    unless defined($view->{$param});
}

sub output_ref {
  my $view = shift;

  return $view->{output};
}

1;

__END__

=head1 NAME

Apache::PageKit::View - Bridge between Apache::PageKit and HTML::Template

=head1 SYNOPSIS

This class is a wrapper class to HTML::Template.  It simplifies the calls to 
output a new template, stores the parameters to be used in a template, and
fills in CGI forms using L<HTML::FillInForm> and resolves <PKIT_*> tags.

=head1 METHODS

The following methods are available to the user as Apache::PageKit::View API.

=over 4

=item new

  my $view = new Apache::PageKit::View;

Constructor for new object.

=item param

This is similar to the L<HTML::Template|HTML::Template/param> method.  It is
used to set template variables.

  $view->param(USERNAME => "John Doe");

Sets the parameter USERNAME to "John Doe".  That is C<E<lt>TMPL_VAR NAME="USERNAME"E<gt>> will be replaced
with "John Doe".

It can also be used to set multiple parameters at once:

  $view->param(firstname => $firstname,
               lastname => $lastname);

=item prepare_module

  $view->prepare_module(34);

Calles the code for the module with id 34 and fills in the module template.

=item prepare_page

  $view->prepare_page;

Calles the code for the page and fills in the page template.

=item prepare_entire_page

Resolves C<E<lt>PKIT_*E<gt>> tags and fills in HTML forms using L<HTML::FillInForm>.

=item output_ref

Returns a reference to the output of the parsed template.

=back

=head1 SEE ALSO

L<Apache::PageKit>, L<HTML::FillInForm>, L<HTML::Template>

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
