package Apache::PageKit::Model;

# $Id: Model.pm,v 1.6 2001/01/10 07:23:51 tjmather Exp $

use integer;
use strict;
use HTML::FormValidator;

sub new {
  my ($class) = @_;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub pkit_user {
  my $model = shift;
  return $model->{pkit_pk}->{view}->param('pkit_user');
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
  for my $field (@$missings, @$invalids){
    my $begin_name = "PKIT_ERRORFONT_BEGIN_$field";
    # should change color to be user configurable...
    my $begin_value = qq{<font color="#ff000">};
    my $end_name = "PKIT_ERRORFONT_END_$field";
    my $end_value = qq{</font>};
    $model->output_param($begin_name => $begin_value);
    $model->output_param($end_name => $end_value);
  }
  if(@$invalids || @$missings){
    if(@$invalids){
      foreach my $field (@$invalids){
	next unless exists $input_profile->{messages}->{$field};
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
  $model->{pkit_pk}->{page_id} = $page_id;
}

sub pkit_get_page_id {
  my ($model) = @_;
  return $model->{pkit_pk}->{page_id};
}

# currently input_param is just a wrapper around $apr
sub input_param {
  my $model = shift;
  return $model->{pkit_pk}->{apr}->param(@_);
}

# currently output_param is just a wrapper around $view
sub output_param {
  my $model = shift;
  return $model->{pkit_pk}->{view}->param(@_);
}

# used to access and set values of <CONTENT_VAR> and <CONTENT_LOOP> tags
sub content_param {
  my ($model, @p) = @_;
  for my $i (0 .. @p/2){
    $p[$i] = "content:".$p[$i];
  }
  $model->output_param(@p);
}

# this is experimental and subject to change
sub dispatch {
  my ($model, $class, $method) = @_;
  my $dispatch_model = $class->new;
  $dispatch_model->{pkit_pk} = $model->{pkit_pk};
  no strict 'refs';
  return &{$class . '::' . $method}($dispatch_model);
}

sub dbh {return shift->{pkit_pk}->{dbh};}
sub apr {return shift->{pkit_pk}->{apr};}
sub session {return shift->{pkit_pk}->{session};}

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

When deriving classes from Apache::PageKit::Model, keep in mind that
all methods and hash keys that begin with pkit_ are reserved for
future use.

=head1 SYNOPSIS

Method in derived class.

  sub my_method {
    my $model = shift;

    # get database handle, session
    my $dbh = $model->dbh;
    my $session = $model->session;

    # get inputs (from request parameters)
    my $foo = $model->input_param('bar');

    # do some processing

    ...

    # set outputs in template
    $model->output_param(result => $result);
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

It can also be used to set multiple parameters at once by passing a hash:

  $model->output_param(firstname => $firstname,
               lastname => $lastname);

Alternatively you can pass a hash reference:

  $model->output_param({firstname => $firstname,
               lastname => $lastname});

=item content_param

Similar to C<output_param> but sets content variables associated with
the <CONTENT_VAR> and <CONTENT_LOOP> tags.

=item apr

Returns the L<Apache::Request> object.

  my $apr = $model->apr;

=item dbh

Returns a database handle, as specified by the C<MyPageKit::Model::dbi_connect>
method.

  my $dbh = $model->dbh;

=item session

Returns a hash tied to <Apache::PageKit::Session>

  my $session = $model->session;

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

=item pkit_validate_input

Takes an hash reference containing a L<HTML::FormValidator> input profile
and returns true if the request parameters are valid.

  # very simple validation, just check to see if name field was filled out
  my $input_profile = {required => [ qw ( name ) ]};
  # validate user input
  unless($model->pkit_validate_input($input_profile)){
    # user must have not filled out name field, 
    # i.e. $apr->param('name') = $model->input_param('name') is
    # not set, so go back to original form
    $model->pkit_set_page_id('orig_form');
    return;
  }

=back

The following methods should be defined in your L<MyPageKit::Common> module:

=over 4

=item pkit_dbi_connect

Returns database handler, C<$dbh>, which can be accessed by rest of Model
through C<$model-E<gt>dbh>.

=item pkit_session_setup

Returns hash reference to session setup arguments.

=item pkit_auth_credential

Verifies the user-supplied credentials and return a session key.  The
session key can be any string - often you'll use the user ID and
a MD5 hash of a a secret key, user ID, password.

=item pkit_auth_session_key

Verifies the session key (previously generated by C<auth_credential>)
and return the user ID.
This user ID will be fed to C<$model-E<gt>input_param('pkit_user')>.

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
