package Apache::PageKit::Model;

# $Id: Model.pm,v 1.1 2000/12/23 07:15:52 tjmather Exp $

use integer;
use strict;
use HTML::FormValidator;

sub new {
  my ($class, $pk) = @_;
  my $self = {pk => $pk};
  bless $self, $class;
  return $self;
}

sub is_error_field {
  my ($model, $field) = @_;
  return exists $model->{error_fields}->{$field};
}

sub validate_input {
  my ($model, $input_profile) = @_;

  my $pk = $model->{pk};
  my $apr = $pk->{apr};

  my $validator = new HTML::FormValidator({default => $input_profile});

  # put the data from the Apache::Request into a %fdat hash so HTML::FormValidator can read it
  my %fdat = ();
  foreach my $field ($apr->param()){
    $fdat{$field} = $apr->param("$field");
  }

  # put Apache::PageKit object in pagekit_object
  $fdat{'pkit_object'} = $pk;

  my ($valids, $missings, $invalids, $unknowns) = $validator->validate(\%fdat, 'default');
  # used to change apply changes from filter to apr
  while (my ($key, $value) = each %$valids){
    $apr->param($key,$value);
  }
  # used to change undef values to "", in case db field is defined as NOT NULL
  for my $field (keys %fdat){
    $valids->{$field} ||= "";
  }
  $model->{error_fields} = {};
  for my $field (@$missings, @$invalids){
    $model->{error_fields}->{$field} = 1;
  }
  if(@$invalids || @$missings){
    if(@$invalids){
      foreach my $field (@$invalids){
	my $value = $fdat{$field};
	# gets error message for that field which was filled in incorrectly
	my $msg = $input_profile->{messages}->{$field};

	# substitutes the value the user entered in the error message
	$msg =~ s/\%\%VALUE\%\%/$value/g;
	$pk->message($msg,
		     is_error => 1);
      }
      $pk->message("Please try again.",
		  is_error => 1);
#      $error_message .= qq{Please try again. <p>};
    } else {
      # no invalid data, just missing fields
      $pk->message(qq{You did not fill out all the required fields.  Please fill the <font color="#ff0000">red</font> fields.});
    }
    return;
  }
  if ($valids){

    # undocumented, will go away...
    $pk->{fdat} = $valids;

    return 1;
  }
}
1;

__END__

=head1 NAME

Apache::PageKit::Model - Form validation.

=head1 DESCRIPTION

This module contains a wrapper to L<HTML::FormValidator>.
It validates the form data
from the L<Apache::Request> object contained in the L<Apache::PageKit> object.

=head1 SYNOPSIS

  $model = Apache::PageKit::Model($pk);

  my $ok = $model->validate_input($input_profile);

  if($ok){
    # get validated, filtered form data
    my $apr = $pk->{apr};
    $fdat = map { $_ => $apr->param($_) } $apr->param;
  } else {
    # not valid, check to see error fields
    if($model->is_error_field('name'));
    $pk->message('You filled your name incorrecty.');
  }

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
