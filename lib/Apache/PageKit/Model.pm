package Apache::PageKit::Model;

# $Id: Model.pm,v 1.33 2001/05/19 22:20:36 tjmather Exp $

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

  my $array_ref = $model->output('pkit_messages') || [];
  push @$array_ref, {pkit_message => $message,
		    pkit_is_error => $options->{'is_error'}};
  $model->output('pkit_messages',$array_ref);
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
  if(my $pkit_messages = $model->output('pkit_messages')){
    my $add_url = join("", map { "&pkit_" . ($_->{pkit_is_error} ? "error_" : "") . "messages=" . Apache::Util::escape_uri($_->{pkit_message}) } @$pkit_messages);
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
