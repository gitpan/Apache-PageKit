package Apache::PageKit::View;

# $Id: View.pm,v 1.5 2000/10/31 22:51:23 tjmather Exp $

use integer;
use strict;

# stores includes that are cached so we can we can pass cached=>1 to HTML::Template
$Apache::PageKit::View::cache_include = {};

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

  my $apr = $pk->{apr};
  my $session = $pk->{session};

  $view->{template_root} = $apr->dir_config('PKIT_TEMPLATE_ROOT') || $apr->document_root;

  $view->{templateOptions} = {
			      # don't die when we set a parameter that is not in the template
			      die_on_bad_params=>0,
			      # built in __FIRST__, __LAST__, etc vars
			      loop_context_vars=>1,
			      global_vars=>1,
			     };

  # set PKIT_NETSCAPE or PKIT_INTERNET_EXPLORER tag
  my $agent = $apr->header_in('User-Agent');
  if($agent =~ /MSIE/){
    $view->param(PKIT_INTERNET_EXPLORER => 1);
  } elsif ($agent =~ /Mozilla/){
    $view->param(PKIT_NETSCAPE => 1);
  }

  # get Locale settings
  # only supports one langauge, should entend to more languages later...
  my @accept_language = map {substr($_,0,2) } split(", ",$apr->header_in('Accept-Language'));

  if(my $lang = $apr->param('pkit_lang')){
    $session->{'pkit_lang'} = $lang;
    unshift @accept_language, $lang;
  } elsif ($session){
    unshift @accept_language, $session->{'pkit_lang'} if exists $session->{'pkit_lang'};
  }

  $view->{lang} = [ @accept_language ];
}

sub prepare_include {
  my ($view, $include_id) = @_;
  my $pk = $view->{pk};
  my $info = $pk->{info};

#  print "template_name_2 -> $include_id<br>";

  $pk->include_code($include_id);

  my $template_name = "/Include/" . $include_id;

  my $pk = $view->{pk};

  my $options = {};
  my $template_cache = $info->get_attr('template_cache');
  if($template_cache eq 'shared'){
    $options->{shared_cache} = 1;
    $Apache::PageKit::View::cache_include->{$include_id} = 'shared';
  } elsif ($template_cache eq 'normal'){
    $options->{cache} = 1;
    $Apache::PageKit::View::cache_include->{$include_id} = 'normal';
  } elsif ($Apache::PageKit::View::cache_include->{$include_id} eq 'normal'){
    $options->{cache} = 1;
  } elsif ($Apache::PageKit::View::cache_include->{$include_id} eq 'shared'){
    $options->{shared_cache} = 1;
  }

  my $output = $view->prepare_template($template_name,
				       $options);
#  $view->param("PKIT_INCLUDE:$include_id" => $output);
  return $output;
}

sub template_file_exists {
  my ($view, $page_id) = @_;
  my $template_file = $view->{template_root} . "/Page/" . $page_id . '.tmpl';
  return 1 if (-e "$template_file");
  return 0;
}


#  my $pkit_link_ref = sub {
sub pkit_link {
  my ($view, $page_id, $query_string) = @_;
  my $pk = $view->{pk};
  my $apr = $pk->{apr};
  my $info = $pk->{info};

  my $orig_page_id = $page_id;
  
  # resolve page_id from url in link, if necessary
  $page_id = $info->page_id_match($page_id)
    unless $info->page_exists($page_id);
  
  my $protocal = ($info->get_attr('is_secure',$page_id) eq 'yes') ? 'https://' : 'http://';
  
  if($info->get_attr('is_popup',$page_id) eq 'yes'){
    $view->param(pkit_java_script_code => 1);
    my $domain = (split(':',$apr->headers_in->{'Host'}))[0];
    my $popup_height = $info->get_attr('popup_height',$page_id);
    my $popup_width = $info->get_attr('popup_width',$page_id);
    return qq{javascript:openWindow('http://} . $domain . qq{/} . $orig_page_id . $query_string . qq{',$popup_width,$popup_height)};
  } elsif ($apr->dir_config('PKIT_PAGE_DOMAIN') eq 'on' && (my $domain = $info->get_attr('domain',$page_id))){
    return qq{$protocal$domain/$orig_page_id$query_string};
  } else {
    return qq{/$orig_page_id$query_string};
  }
}

sub prepare_output {
  my $view = shift;
  my $pk = $view->{pk};
  my $info = $pk->{info};
  my $apr = $pk->{apr};

  my $page_id = $pk->{page_id};

#  $info->get_content;

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

#  $output =~ s/<PKIT_INCLUDE (NAME=)?"?([^"]*)"?>/$2/eig;

  $output =~ s/<PKIT_LINK (PAGE=)?"?(.*?)(\?.*?)?"?>/qq{<a href="} . $view->pkit_link($2, $3) . qq{">}/eig;
  $output =~ s/<\/PKIT_LINK>/<\/a>/ig;

  my @params = $apr->param;

  if($view->param('pkit_java_script_code')){
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

  $output =~ s/<PKIT_ERRORFONT (NAME=)?"?([^"]*?)"?>(.*?)<\/PKIT_ERRORFONT>/&$pkit_errorfont_ref($2,$3)/eigs;

  # make html forms "sticky"
  if ($pk->{fill_in_form} && @params && $output =~ m/<form/i){
    $view->{fif} ||= HTML::FillInForm->new();
    $output = $view->{fif}->fill(scalarref=>\$output,
				    fobject=>$apr);
  }

  $view->{output} = \$output;
}

# common code for page, view and include templates
sub prepare_template {
  my $view = shift;
  my $template_name = shift;
  my $options = shift;

  my $pk = $view->{pk};

#  print "template_name -> $template_name<br>";

  my $filename;
  my $pkit_view = $pk->{apr}->param('pkit_view');
  if($pkit_view && -e "$view->{template_root}$template_name.$pkit_view.tmpl"){
    $filename = "$view->{template_root}$template_name.$pkit_view.tmpl";
#  } elsif ($pkit_view && -e "$view->{template_root}$pkit_view/$template_name.tmpl"){
#    $filename = "$view->{template_root}$pkit_view/$template_name.tmpl";
  } else {
    $filename = "$view->{template_root}$template_name.tmpl";
  }

  if($view->param('pkit_admin')){
    # add edit link for pkit_admins
    my $array_ref = $view->param('pkit_edit');
    my ($template_id) = ($template_name =~ m(^/(.*)$));
    push @$array_ref, {template => $template_id};

    # also add links for TMPL_INCLUDES
#    open TEMPLATE, $filename;
#    local $/ = undef;
#    my $template = <TEMPLATE>;
#    close TEMPLATE;

#    my $pkit_done = $view->param("pkit_done");

#    while ($template =~ m(<PKIT_INCLUDE NAME="(.*?)">)ig){
#      push @$array_ref, {template => "Include/$1"};
#    }

    $view->param('pkit_edit',$array_ref);
  }

  my $template = HTML::Template->new_file($filename,
					  %{$view->{templateOptions}},
					  %$options);

  # process <TMPL_VAR NAME="PKIT_INCLUDE:include_id"> tags
#  my @includes = map { m/^PKIT_INCLUDE:(.*?)$/i } $template->param;

#  for (@includes){
#    $view->prepare_include($_);
#  }
  $view->_apply_param($template);

  my $output = $template->output;

  $output =~ s/<PKIT_INCLUDE (NAME=)?"?([^"]*)"?>/$view->prepare_include($2)/eig;

  return $output;
}

sub _apply_param {
  my ($view, $template) = @_;

  my $pk = $view->{pk};

  my $page_id = $pk->{page_id};

  # get params from XML file
  my $param_hashref = $pk->{info}->get_param_hashref;
  while (my ($key, $value) = each %$param_hashref){
    $template->param($key,$value);
  }

  # get params from GET/POST request
  foreach my $key ($pk->{apr}->param){
    $template->param($key,$pk->{apr}->param($key))
      if $template->query(name => $key) eq 'VAR';
  }

  # get params from $view object
  foreach my $key ($view->param){
    my $value = $view->param($key);
    unless (ref($value) eq 'ARRAY' && $template->query(name => $key) ne 'LOOP'){
      $template->param($key, $value);
    } else {
      # avoid attempt to set parameter 'portfolio' with an array ref - parameter is not a TMPL_LOOP!
      # error in HTML::Template
      $template->param($key, scalar @$value);
    }
  }

  # set laugauge localization, if applicable
  while(my $lang = shift @{$view->{lang}}){
    if ($template->query(name => "PKIT_LANG_$lang")){
      $template->param("PKIT_LANG_$lang" => 1);
      last;
    }
  }
}

# prepare whole page, starting with view
sub prepare_entire_page {
  my ($view) = @_;
  my $pk = $view->{pk};
  my $apr = $pk->{apr};
  my $info = $pk->{info};

#  my $page_view = $info->get_attr('view');

#  my $template_name = "/View/" . $page_view;

#  my $options = {};
#  if($pk->{view_cache} eq 'shared'){
#    $options->{shared_cache} = 1;
#  } elsif ($pk->{view_cache} eq 'normal'){
#    $options->{cache} = 1;
#  }

#  my $output = $view->prepare_template($template_name,
#				       $options);

  my $output = $view->param('PKIT_PAGE');
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

=item prepare_include

  $view->prepare_include(34);

Calles the code for the include with id 34 and fills in the include template.

=item prepare_output

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

=cut
