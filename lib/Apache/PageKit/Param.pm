package Apache::PageKit::Param;

# $Id: Param.pm,v 1.4 2001/05/29 00:43:34 tjmather Exp $

use strict;

sub new($$) {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  return $self;
}

# param method - can be called in two forms
# when passed two arguments ($name, $value), it sets the value of the 
# $name attributes to $value
# when passwd one argument ($name), retrives the value of the $name attribute
sub param {
  my ($self, @p) = @_;

  unless(@p){
    # the no-parameter case - return list of parameters
    return () unless defined($self) && $self->{'pkit_parameters'};
    return () unless @{$self->{'pkit_parameters'}};
    return @{$self->{'pkit_parameters'}};
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
      $self->_add_parameter($name);
      $self->{$name} = $value;
    }
  } else {
    $name = $p[0];
  }
  return $self->{$name} if defined($name);
}

sub _add_parameter {
  my ($self, $param) = @_;
  return unless defined $param;
  push (@{$self->{'pkit_parameters'}},$param)
    unless defined($self->{$param});
}

1;
