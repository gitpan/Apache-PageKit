package Apache::PageKit::Model;

# $Id: Model.pm,v 1.30 2001/05/13 03:42:36 tjmather Exp $

use integer;
use strict;
use HTML::FormValidator;

use Apache::Constants qw(REDIRECT);

use Data::Dumper;

sub new {
  my $class = shift;
  my $self = { @_ };
  bless $self, $class;
  $self->{pkit_pk}->{output_param_object} ||= Apache::PageKit::Param->new();
  $self->{pkit_pk}->{fillinform_object} ||= Apache::PageKit::Param->new();
  return $self;
}

sub pkit_get_session_id {
  my $model = shift;
  return $model->{pkit_pk}->{session}->{_session_id};
}

sub pkit_get_server_id {
  my $model = shift;
  my $apr = $model->{pkit_pk}->{apr};
  return $apr->dir_config('PKIT_SERVER') if $apr;
}

sub pkit_root {
  my $model = shift;
  my $apr = $model->{pkit_pk}->{apr};
  return $apr->dir_config('PKIT_ROOT') if $apr;
}

sub pkit_get_orig_uri {
  my $model = shift;
  return $model->{pkit_pk}->{apr}->notes('orig_uri');
}

sub pkit_get_page_id {
  my $model = shift;
  return $model->{pkit_pk}->{page_id};
}

sub pkit_user {
  my $model = shift;
  return $model->{pkit_pk}->{apr}->connection->user;
}

sub pkit_set_errorfont {
  my ($model, $field) = @_;

  my $begin_name = "PKIT_ERRORFONT_BEGIN_$field";
  # should change color to be user configurable...
  my $begin_value = qq{<font color="#ff000">};
  my $end_name = "PKIT_ERRORFONT_END_$field";
  my $end_value = qq{</font>};
  $model->output($begin_name => $begin_value);
  $model->output($end_name => $end_value);
}

sub pkit_validate_input {
  my ($model, $input_profile) = @_;

  my $validator = new HTML::FormValidator({default => $input_profile});

  # put the data from input into a %fdat hash so HTML::FormValidator can read it
  my $input_hashref = $model->pkit_input_hashref;

  # put derived Model object in pkit_model
  # so form validation can access $dbh, etc
  # this is used, for example, to see if a login already exists
  $input_hashref->{'pkit_model'} = $model;

  my ($valids, $missings, $invalids, $unknowns) = $validator->validate($input_hashref, 'default');
  # used to change apply changes from filter to apr
  while (my ($key, $value) = each %$valids){
    $model->input($key,$value);
  }

  # used to change undef values to "", in case db field is defined as NOT NULL
  for my $field (keys %$input_hashref){
    $valids->{$field} ||= "";
  }

  for my $field (@$missings, @$invalids){
    $model->pkit_set_errorfont($field);
  }
  if(@$invalids || @$missings){
    if(@$invalids){
      foreach my $field (@$invalids){
	next unless exists $input_profile->{messages}->{$field};
	my $value = $input_hashref->{$field};
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

sub pkit_input_hashref {
  my $model = shift;
  return $model->{pkit_input_hashref} if
    exists $model->{pkit_input_hashref};
  my $input_hashref = {};
  for my $key ($model->input){
    $input_hashref->{$key} = $model->input($key);
  }
  $model->{pkit_input_param_ref} = $input_hashref;
}

sub pkit_message {
  my $model = shift;
  my $message = shift;

  my $options = {@_};

  my $array_ref = $model->output('pkit_message') || [];
  push @$array_ref, {pkit_message => $message,
		    pkit_is_error => $options->{'is_error'}};
  $model->output('pkit_message',$array_ref);
}

sub pkit_internal_redirect {
  my ($model, $page_id) = @_;
  $model->{pkit_pk}->{page_id} = $page_id;
}

sub input_param {
  warn "input_param is depreciated - use input, fillinform or pnotes instead";
  input(@_);
}

# currently input_param is just a wrapper around $apr
sub input {
  my $model = shift;
  if (exists $model->{pkit_pk} && exists $model->{pkit_pk}->{apr}){
    if(wantarray){
      # deal with multiple value containing parameters
      my @list = $model->{pkit_pk}->{apr}->param(@_);
      return @list;
    } else {
      return $model->{pkit_pk}->{apr}->param(@_);
    }
  } else {
    return $model->_param("input",@_);
  }
}

sub fillinform {
  return shift->{pkit_pk}->{fillinform_object}->param(@_);
}

sub output_param {
  warn "output_param is depreciated - use output instead";
  output(@_);
}

# currently output_param is just a wrapper around $view
sub output {
  return shift->{pkit_pk}->{output_param_object}->param(@_);
#  if (exists $model->{pkit_pk}){
#    return $model->{pkit_pk}->{view}->param(@_);
#  } else {
#  }
}

sub pnotes {
  return shift->{pkit_pk}->{apr}->pnotes(@_);
}

# put here so that it can be overriden in derived classes
sub pkit_get_default_page {
  return shift->{pkit_pk}->{config}->get_global_attr('default_page');
}

sub create {
  my ($model, $class) = @_;
  my $create_model = $class->new(pkit_pk => $model->{pkit_pk});
  return $create_model;
}

# this is experimental and subject to change
sub dispatch {
  warn "dispatch is depreciated - use create instead";
  my ($model, $class, $method, @args) = @_;
  my $dispatch_model = $class->new(pkit_pk => $model->{pkit_pk});
#  $dispatch_model->{pkit_pk} = $model->{pkit_pk} if exists $model->{pkit_pk};
  no strict 'refs';
  return &{$class . '::' . $method}($dispatch_model, @args);
}

sub dbh {
  my $model = shift;
  if (exists $model->{pkit_pk}->{dbh}){
    return $model->{pkit_pk}->{dbh};
  } else {
    $Apache::Model::dbh = $model->pkit_dbi_connect
      unless defined($Apache::Model::dbh) && $Apache::Model::dbh->ping;
    return $Apache::Model::dbh;
  }
}

sub apr {return shift->{pkit_pk}->{apr};}
sub session {return shift->{pkit_pk}->{session};}

sub pkit_redirect {
  my ($model, $url) = @_;
  my $pk = $model->{pkit_pk};
  my $apr = $pk->{apr};
  if(my $pkit_message = $model->output('pkit_message')){
    my $add_url = join("", map { "&pkit_" . ($_->{pkit_is_error} ? "error_" : "") . "message=" . Apache::Util::escape_uri($_->{pkit_message}) } @$pkit_message);
    $add_url =~ s!^&!?! unless $url =~ m/\?/;
    $url .= $add_url;
  }
  $apr->headers_out->set(Location => $url);
  $pk->{status_code} = REDIRECT;
}

sub pkit_query {
  my ($model, @p) = @_;
  my $pk = $model->{pkit_pk};
  my $view = $pk->{view};

  # will need to change once Template-Toolkit is supported
  unless(exists $view->{record}){
    $pk->open_view;
  }

  return $view->{record}->{html_template}->query(@p);
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
    my $foo = $model->input('bar');

    # do some processing

    ...

    # set outputs in template
    $model->output(result => $result);
  }

=head1 METHODS 

=head2 API to be used in derived classes

The following methods are available to the user as
Apache::PageKit::Model API.

=over 4

=item input

Gets requested parameter from the request object C<$apr>.

  my $value = $model->input($key);

If called without any parameters, gets all available input parameters:

  my @keys = $model->input;

=item pkit_input_hashref

This method fetches all of the parameters from the request object C<$apr>,
returning a reference to a hash containing the parameters as keys, and
the parameters' values as values.  Note a multivalued parameters
is returned as a reference to an array.

  $params = $model->pkit_input_hashref;

=item fillinform

Used with L<HTML::FillInForm> to fill in HTML forms.  Useful for example
when you want to fill an edit form with data from the database.

  $model->fillinform(email => $email);

=item pnotes

Wrapper to mod_perl's C<pnotes> function, used to pass values from
one handler to another.

For example you can set the userID when the user gets authenticated:

  $model->pnotes(user_id => $user_id);

=item output

This is similar to the L<HTML::Template|HTML::Template/param> method.  It is
used to set <MODEL_*> template variables.

  $model->output(USERNAME => "John Doe");

Sets the parameter USERNAME to "John Doe".
That is C<E<lt>MODEL_VAR NAME="USERNAME"E<gt>> will be replaced
with "John Doe".

It can also be used to set multiple parameters at once by passing a hash:

  $model->output(firstname => $firstname,
               lastname => $lastname);

Alternatively you can pass a hash reference:

  $model->output({firstname => $firstname,
               lastname => $lastname});

Note, to set the bread crumb for the <PKIT_LOOP NAME="BREAD_CRUMB"> tag,
use the following code:

  $model->output(pkit_bread_crumb =>
		       [
			{ pkit_page => 'toplink', pkit_name='Top'},
			{ pkit_page => 'sublink', pkit_name='Sub Class'},
			{ pkit_name => 'current page' },
		       ]
		      );

=item pkit_query

Basically a wrapper to the L<HTML::Template/"query()"> method of HTML::Template:

  my $type = $model->pkit_query(name => 'foo');

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

Note that the message is passed along in the URI if you perform a
redirect using C<pkit_redirect>.

=item pkit_internal_redirect

Resets the page_id. This is usually used "redirect" to different template.

  $model->pkit_internal_redirect($page_id);

=item pkit_redirect

Redirect to another URL.

  $model->pkit_redirect("http://www.pagekit.org/");

Redirects user to the PageKit home page.

It is strongly recommend that you use this method on pages where a
query that changes the state of the application is executed.  Typically
these are POST queries that update the database.

Note that this passes along the messages set my C<pkit_message> if applicable.

=item pkit_set_errorfont

Sets the corresponding C<&lt;PKIT_ERRORFONT&gt;> tag in the template.  Useful
for implementing your own custom constraints.

  $model->pkit_set_errorfont('state');

Sets C<&lt;PKIT_ERRORFONT NAME="state"&gt;> to C<&lt;font color="red"&gt;>

=item pkit_validate_input

Takes an hash reference containing a L<HTML::FormValidator> input profile
and returns true if the request parameters are valid.

  # very simple validation, just check to see if name field was filled out
  my $input_profile = {required => [ qw ( name ) ]};
  # validate user input
  unless($model->pkit_validate_input($input_profile)){
    # user must have not filled out name field, 
    # i.e. $apr->param('name') = $model->input('name') is
    # not set, so go back to original form
    # if you used a <PKIT_ERRORFONT NAME="name"> tag, then it will be set to
    # red
    $model->pkit_internal_redirect('orig_form');
    return;
  }

=item pkit_get_orig_uri

Gets the original URI requested.

=item pkit_get_page_id

Gets page_id.

=item pkit_get_server_id

Gets the server_id for the server, as specified by the
C<PKIT_SERVER> directive in the httpd.conf file.

=item pkit_get_session_id

Gets the session id if you have set up session management using
L<pkit_session_setup>.  Note the following code is equivalent:

  my $session_id = $model->pkit_get_session_id;
  my $session_id = $model->session->{_session_id};

=item pkit_root

Gets the PageKit root directory, as defined by PKIT_ROOT in your
httpd.conf file.

  my $pkit_root = $model->pkit_root

=item pkit_user

Gets the user_id from C<$apr->connection->user>, as set by the return
value of C<pkit_auth_session_key>.

=back

=head2 Methods to be defined in your base Model class.

The following methods should be defined in your base module as defined
by C<model_base_class> in Config.xml:

=over 4

=item pkit_dbi_connect

Returns database handler, C<$dbh>, which can be accessed by rest of Model
through C<$model-E<gt>dbh>.

=item pkit_session_setup

Returns hash reference to L<Apache::PageKit::Session> session setup arguments.

=item pkit_auth_credential

Verifies the user-supplied credentials and return a session key.  The
session key is a string that is stored on the user's computer using cookies.
Often you'll use the user ID and a MD5 hash of a a secret key, user ID, password.

Note that the string returned should not contain any commas, spaces, or semi-colons.

=item pkit_auth_session_key

Verifies the session key (previously generated by C<auth_credential>)
and return the user ID.
The returned user ID will be fed to C<$apr->connection->user>.

=item pkit_common_code

Code that gets called before the page and component code for every page on
the site.

=item pkit_post_common_code

Code that gets called after the page and component code is executed.
Note that this is experimental and may change in future releases.

=item pkit_cleanup_code

One use for this is to cleanup any database handlers:

sub pkit_cleanup_code {
  my $model = shift;
  my $dbh = $model->dbh;
  $dbh->disconnect;
}

Although a better solution is to use L<Apache::DBI>.

=item pkit_fixup_uri

Pre-processes the URI so that it will match the page_id's used by PageKit
to dispatch the model code and find the template and content files.

  sub pkit_fixup_uri {
    my ($model, $uri) = @_;

    $uri =~ s!^/pagekit!!;
    return $uri;
  }

In this example, the request for http://yourwebsite/pagekit/myclass/mypage would
get dispatched to the mypage method of the myclass class, and the View/Default/myclass/mypage.tmpl template and/or the Content/myclass/mypage.xml XML file.

See also C<uri_prefix> in L<Apache::PageKit::Config>.

=item pkit_get_default_page

If no page is specified, then this subroutine will return the page_id
of the page that should be displayed.  You only have to provide this
routine if you wish to override the default method, which simply
returns the C<default_page> attribute as listed in the C<Config.xml> file.

=item pkit_output_filter

Filters the output from the PageKit handler.  Should only use when necessary,
a better option is to modify the templates directly.

Here we filter the image links to that they point to the secure site if we
are on a secure page (the only good use of pkit_output_filter that I know of)

  sub pkit_output_filter {
    my ($model, $output_ref) = @_;
    if($model->apr->parsed_uri->scheme eq 'https'){
      $$output_ref =~ s(http://images.yourdomain.com/)(https://images.yourdomain.com/)g;
    }
  }

=back

=head1 SEE ALSO

L<Apache::PageKit>, L<HTML::FormValidator>

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 COPYRIGHT

Copyright (c) 2000, 2001 AnIdea Corporation.  All rights Reserved.  PageKit is
a trademark of AnIdea Corporation.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
