package Apache::PageKit::Model;

# $Id: Model.pm,v 1.3 2001/01/03 06:45:19 tjmather Exp $

use integer;
use strict;
use HTML::FormValidator;

sub new {
  my ($class, $apr) = @_;
  my $self = {apr => $apr};
  bless $self, $class;
  return $self;
}

sub pkit_is_error_field {
  my ($model, $field) = @_;
  return exists $model->{pkit_error_fields}->{$field};
}

sub pkit_validate_input {
  my ($model, $input_profile) = @_;

  my $validator = new HTML::FormValidator({default => $input_profile});

  # put the data from input_param into a %fdat hash so HTML::FormValidator can read it
  my %fdat = ();
  foreach my $field ($model->input_param()){
    $fdat{$field} = $model->input_param("$field");
  }

  # put derived Model object in pkit_model
  # so form validation can access $dbh, etc
  # this is used, for example, to see if a login already exists
  $fdat{'pkit_model'} = $model;

  my ($valids, $missings, $invalids, $unknowns) = $validator->validate(\%fdat, 'default');
  # used to change apply changes from filter to apr
  while (my ($key, $value) = each %$valids){
    $model->input_param($key,$value);
  }
  # used to change undef values to "", in case db field is defined as NOT NULL
  for my $field (keys %fdat){
    $valids->{$field} ||= "";
  }
  $model->{pkit_error_fields} = {};
  for my $field (@$missings, @$invalids){
    $model->{pkit_error_fields}->{$field} = 1;
  }
  if(@$invalids || @$missings){
    if(@$invalids){
      foreach my $field (@$invalids){
	my $value = $fdat{$field};
	# gets error message for that field which was filled in incorrectly
	my $msg = $input_profile->{messages}->{$field};

	# substitutes the value the user entered in the error message
	$msg =~ s/\%\%VALUE\%\%/$value/g;
	$model->pkit_message($msg,
			is_error => 1);
      }
      $model->pkit_message("Please try again.",
		  is_error => 1);
    } else {
      # no invalid data, just missing fields
      $model->pkit_message(qq{You did not fill out all the required fields.  Please fill the <font color="#ff0000">red</font> fields.});
    }
    return;
  }
  if ($valids){
    return 1;
  }
}

sub pkit_message {
  my $model = shift;
  my $message = shift;

  my $options = {@_};

  my $array_ref = $model->output_param('pkit_message') || [];
  push @$array_ref, {pkit_message => $message,
		    pkit_is_error => $options->{'is_error'}};
  $model->output_param('pkit_message',$array_ref);
}

sub pkit_set_page_id {
  my ($model, $page_id) = @_;
  $model->{pkit_page_id} = $page_id;
}

sub pkit_get_page_id {
  my ($model) = @_;
  return $model->{pkit_page_id};
}

# currently input_param is just a wrapper around $apr
sub input_param {
  my $model = shift;
  return $model->{apr}->param(@_);
}

# param method - can be called in two forms
# when passed two arguments ($name, $value), it sets the value of the 
# $name attributes to $value
# when passwd one argument ($name), retrives the value of the $name attribute
# used to access and set values of <MODEL_*> tags
sub output_param {
  my ($model, @p) = @_;

  unless(@p){
    # the no-parameter case - return list of parameters
    return () unless defined($model) && $model->{'pkit_parameters'};
    return () unless @{$model->{'pkit_parameters'}};
    return @{$model->{'pkit_parameters'}};
  }
  my ($name, $value);
  if (@p > 1){
    die "param called with odd number of parameters" unless ((@p % 2) == 0);
    while(($name, $value) = splice(@p, 0, 2)){
      $model->_add_parameter($name);
      $model->{pkit_param}->{$name} = $value;
    }
  } else {
    $name = $p[0];
  }
  return $model->{pkit_param}->{$name};
}

# used to access and set values of <CONTENT_VAR> and <CONTENT_LOOP> tags
sub content_param {
  my ($model, @p) = @_;
  for my $i (0 .. @p/2){
    $p[$i] = "content:".$p[$i];
  }
  $model->output_param(@p);
}

sub _add_parameter {
  my ($content, $param) = @_;
  return unless defined $param;
  push (@{$content->{'pkit_parameters'}},$param)
    unless defined($content->{$param});
}

1;

__END__

=head1 NAME

Apache::PageKit::Model - Base Model Class

=head1 DESCRIPTION

This class provides a base class for the Modules implementing
the backend business logic for your web site.

This module also contains a wrapper to L<HTML::FormValidator>.
It validates the form data from the L<Apache::Request> object contained
in the L<Apache::PageKit> object.

=head1 SYNOPSIS

  my $model = Apache::PageKit::Model->new($apr);

  my $ok = $model->pkit_validate_input($input_profile);

  if($ok){
    # get validated, filtered form data
    $fdat = map { $_ => $model->input_param($_) } $model->input_param;
  } else {
    # not valid, check to see error fields
    if($model->is_error_field('name'));
    $model->pkit_message('You filled your name incorrecty.');
  }

=head1 METHODS 

The following methods are available to the user as
Apache::PageKit::Model API.

=over 4

=item input_param

Gets requested parameter from the request object C<$apr>.

  my $value = $model->input_param($key);

If called without any parameters, gets all available input parameters:

  my @keys = $model->input_param;

Can also be used to set parameter that Model gets as input.  For example
you can set the userID when the user gets authenticated:

  $model->input_param(pkit_user => $userID);

=item output_param

This is similar to the L<HTML::Template|HTML::Template/param> method.  It is
used to set <MODEL_*> template variables.

  $model->output_param(USERNAME => "John Doe");

Sets the parameter USERNAME to "John Doe".
That is C<E<lt>MODEL_VAR NAME="USERNAME"E<gt>> will be replaced
with "John Doe".

It can also be used to set multiple parameters at once:

  $model->output_param(firstname => $firstname,
               lastname => $lastname);

=item content_param

Similar to C<output_param> but sets content variables associated with
the <CONTENT_VAR> and <CONTENT_LOOP> tags.

=item pkit_message

Displays a special message to the user.  The message can displayed using the
C<E<lt>PKIT_LOOP NAME="MESSAGE"E<gt> E<lt>/PKIT_LOOPE<gt>> code.

You can add a message from the Model code:

  $model->pkit_message("Your listing has been deleted.");

To add an error message (typically highlighted in red), use

  $model->pkit_message("You did not fill out the required fields.",
               is_error => 1);

=item pkit_set_page_id

Sets the page_id. This is usually used "redirect" to different template.

  $model->pkit_set_page_id($page_id);

=item pkit_get_page_id

Used internally by PageKit (if nowhere else) to retreive the Page ID
set by C<pkit_set_page_id>.

  my $page_id = $model->pkit_get_page_id;

=back

=head1 SEE ALSO

L<Apache::PageKit>, L<HTML::FormValidator>

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
