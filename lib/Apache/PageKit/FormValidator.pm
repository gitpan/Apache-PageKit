package Apache::PageKit::FormValidator;

# $Id: FormValidator.pm,v 1.3 2000/09/23 22:33:40 tjmather Exp $

use integer;
use strict;
use HTML::FormValidator;

#use vars qw( @ISA );

#@ISA = qw( HTML::FormValidator );

#use base "HTML::FormValidator";

sub new {
  my ($class, $input_profile) = @_;
  my $self = {};
  bless $self, $class;
  $self->{input_profile} = $input_profile;
  return $self;
}

sub is_error_field {
  my ($self, $field) = @_;
  return exists $self->{error_fields}->{$field};
}

sub validate {
  my ($self, $pk) = @_;

  my $profile = $pk->{page_id};

  # if no input_profile for profile, page doesn't need to validated,
  # so return valid
  return 1 unless exists $self->{input_profile}->{$profile};

  my $apr = $pk->{apr};

  my $validator = new HTML::FormValidator($self->{input_profile});

  # put the data from the Apache::Request into a %fdat hash so HTML::FormValidator can read it
  my %fdat = ();
  foreach my $field ($apr->param()){
    $fdat{$field} = $apr->param("$field");
  }

  # put Apache::PageKit object in pagekit_object
  $fdat{'pkit_object'} = $pk;

  my ($valids, $missings, $invalids, $unknowns) = $validator->validate(\%fdat, $profile);
  # used to change apply changes from filter to apr
  while (my ($key, $value) = each %$valids){
    $apr->param($key,$value);
  }
  # used to change undef values to "", in case db field is defined as NOT NULL
  for my $field (keys %fdat){
    $valids->{$field} ||= "";
  }
  $self->{error_fields} = {};
  for my $field (@$missings, @$invalids){
    $self->{error_fields}->{$field} = 1;

    # sets the parameters so that the names of the fields will appear 
    # _red_ on the html template at the <PKIT_ERRORFONT> tags

    # this sets the font to be red
    #$view->param("pkit_error:" . $field . ":begin", qq{<font color="#ff0000">});

    # this closes the font tag
    #$view->param("pkit_error:" . $field . ":end", qq{</font>});
  }
  if(@$invalids || @$missings){
    if(@$invalids){
      foreach my $field (@$invalids){
	my $value = $fdat{$field};
	# gets error message for that field which was filled in incorrectly
	my $msg = $self->{input_profile}->{$profile}->{messages}->{$field};

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
    $pk->{fdat} = $valids;
    return 1;
  }
}
1;

__END__

=head1 NAME

Apache::PageKit::FormValidator - Validates user input based on Apache::Request object

=head1 DESCRIPTION

This module is a wrapper to L<HTML::FormValidator>.  It validates the form data
from the L<Apache::Request> object contained in the L<Apache::PageKit> object.

=head1 SYNOPSIS

  $validator = Apache::PageKit::FormValidator->new( $input_profile );

  my $ok = $validator->validate($pk);

  if($ok){
    # get validated, filtered form data
    my $apr = $pk->{apr};
    $fdat = map { $_ => $apr->param($_) } $apr->param;
  } else {
    # not valid, check to see error fields
    if($validator->is_error_field('name'));
    $pk->message('You filled your name incorrecty.');
  }

=head1 SEE ALSO

L<Apache::PageKit>, L<Apache::View>, L<HTML::FormValidator>, L<HTML::Template>

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
