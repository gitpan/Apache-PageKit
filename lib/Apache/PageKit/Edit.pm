package Apache::PageKit::Edit;

# note that this Model class accesses some of the internals of
# PageKit and should not be used as an example for writing 
# your own Model classes

use vars qw(@ISA);
@ISA = qw(Apache::PageKit::Model);

use strict;

# Editing views
sub open_view {
  my $model = shift;
  my $pk = $model->{pkit_pk};
  my $apr = $pk->{apr};
  my $view = $pk->{view};
  my $pkit_root = $apr->dir_config('PKIT_ROOT');

  my $file = $model->input_param('file');

  open TEMPLATE, "$pkit_root/$file";
  local $/ = undef;

  # we need to escape HTML tags to avoid </textarea>
#  my $content = Apache::Util::escape_html(<PAGE> || "");
  my $content = <TEMPLATE>;
  close TEMPLATE;

  $model->output_param(file => $file);
  $model->output_param(content => $content);
}

sub commit_view {
  my $model = shift;
  my $pk = $model->{pkit_pk};
  my $apr = $pk->{apr};
  my $view = $pk->{view};
  my $pkit_root = $apr->dir_config('PKIT_ROOT');

  my $file = $model->input_param('file');
  my $pkit_done = $model->input_param('pkit_done');
  my $content = $model->input_param('content');

  open TEMPLATE, ">$pkit_root/$file";
  print TEMPLATE $content;
  close TEMPLATE;

  if($pkit_done){
    $model->pkit_redirect($pkit_done);
  }
}

1;

__END__

=head1 NAME

Apache::PageKit::Edit - Web based editing tools for View templates

=head1 SYNOPSIS

This class is a wrapper class to HTML::Template.  It simplifies the calls to 
output a new template, stores the parameters to be used in a template, and
fills in CGI forms using L<HTML::FillInForm> and resolves <PKIT_*> tags.

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
