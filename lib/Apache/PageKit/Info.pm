package Apache::PageKit::Info;

# $Id: Info.pm,v 1.1 2000/08/29 19:01:11 tjmather Exp $

use integer;
use strict;

use vars qw($page_id $ATTR_NAME $VAR_NAME
	    @LOOP_NAME_STACK @ITEM_HASH_REF_STACK @LOOP_ARRAY_REF_STACK %info_hash);

sub new {
  my ($class) = @_;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub _init {
  my ($info) = @_;

  # delete current init
  $info->{page_id_match} = {};

  my $r = Apache->request;

  my $page_info_file = $r->dir_config("PKIT_PAGE_INFO_FILE");

  die "no page info file" unless $page_info_file;

  my $p = XML::Parser->new(Style => 'Subs');

  $p->setHandlers(Default => \&Default);

  $p->parsefile($page_info_file);

  Apache::PageKit->call_plugins($info, 'info_init_handler');
}

sub get_info {
  my ($pk) = @_;

  my $r = Apache->request;

  my $page_info_file = $r->dir_config("PKIT_PAGE_INFO_FILE");

  unless ($info_hash{$page_info_file}){
    $info_hash{$page_info_file} = Apache::PageKit::Info->new();
    $info_hash{$page_info_file}->_init;
  }
  my $info = $info_hash{$page_info_file};

  $info->{pk} = $pk;

  # on production, we don't check for new page file
  return $info if $r->dir_config('PKIT_PRODUCTION') eq 'on';

  my $mtime = (stat $page_info_file)[9];
  if($mtime > $Apache::PageKit::Info::pageMtime{$r->dir_config("PKIT_PAGE_INFO_FILE")}){
    $info->_init;
    $Apache::PageKit::Info::pageMtime{$r->dir_config("PKIT_PAGE_INFO_FILE")} = $mtime;
  }
  return $info;
}

sub page_exists {
  my ($info, $page_id) = @_;
  if (exists $info->{attr}->{$page_id}){
    return 1;
  } else {
    return 0;
  }
}

# optional page_id paramater
sub get_attr {
  my ($info, $attr, $page_id) = @_;

  return unless $info->{pk};
  $page_id ||= $info->{pk}->{page_id};
  return unless $info->{attr}->{$page_id};
  return $info->{attr}->{$page_id}->{$attr};
}

# optional page_id paramater
sub get_param {
  my ($info, $key, $page_id) = @_;
  return unless $info->{pk};
  $page_id ||= $info->{pk}->{page_id};
  return unless $info->{param}->{$page_id};
  return $info->{param}->{$page_id}->{$key};
}

# optional page_id paramater
sub get_param_hashref {
  my ($info, $page_id) = @_;
  return unless $info->{pk};
  $page_id ||= $info->{pk}->{page_id};
  return $info->{param}->{$page_id};
}

sub page_id_by_domain {
  my ($info, $domain) = @_;
  return $info->{domain}->{$domain};
}

# used to match pages to regular expressions in the page_id_match column
sub page_id_match {
  my ($info, $page_id_in) = @_;
  my $page_id_out;
  while(my ($page_id, $reg_exp) = each %{$info->{page_id_match}}){
    my $match = '$page_id_in =~ /' . $reg_exp . '/';
    if(eval $match){
      $info->{pk}->{orig_page_id} = $page_id_in;
      $page_id_out = $page_id;
    }
  }
  $page_id_out;
}

##################################
# methods for parsing XML file

sub SITE {}
sub SITE_ {}

# called at begining <PAGE> tag in XML file
sub PAGE {
  my ($p, $edtype, %attr) = @_;

  my $r = Apache->request;
  my $page_info_file = $r->dir_config("PKIT_PAGE_INFO_FILE");
  my $info = $info_hash{$page_info_file};

  $page_id = $attr{page_id};

  if((my $sub_domain = Apache->request->dir_config('PKIT_SUBDOMAIN')) && $attr{domain}){
    $attr{domain} =~ s/([^.]*)\.([^.]*)$/$sub_domain.$1.$2/;
  }

  while (my ($key, $value) = each %attr){
    next if $key eq 'page_id';
    if($key eq 'page_id_match'){
      $info->{page_id_match}->{$page_id} = $value;
    } else {
      $info->{attr}->{$page_id}->{$key} = $value;
      if($key eq 'is_topdomain' && $value eq 'yes'){
	$info->{domain}->{$attr{domain}} = $page_id;
      }
    }
  }
}

sub PAGE_ {}

# called at the beginning of ATTR tag in XML file
sub ATTR {
  my ($p, $edtype, %attr) = @_;

  $ATTR_NAME = $attr{NAME};
}

sub ATTR_ {
  $ATTR_NAME = undef;
}

sub TMPL_VAR {
  my ($p, $edtype, %attr) = @_;

  $VAR_NAME = $attr{NAME};
}

sub TMPL_VAR_ {
  $VAR_NAME = undef;
}

sub TMPL_LOOP {
  my ($p, $edtype, %attr) = @_;

  push @LOOP_NAME_STACK, $attr{NAME};
  push @LOOP_ARRAY_REF_STACK, [];
  push @ITEM_HASH_REF_STACK, {};
}

sub TMPL_LOOP_ { 
  my $r = Apache->request;
  my $info = $info_hash{$r->dir_config("PKIT_PAGE_INFO_FILE")};
  if(scalar @LOOP_NAME_STACK == 1){
    # top LOOP element
    $info->{param}->{$page_id}->{$LOOP_NAME_STACK[0]} = $LOOP_ARRAY_REF_STACK[-1];
  } else {
    # nested LOOP element
    $ITEM_HASH_REF_STACK[-2]->{$LOOP_NAME_STACK[-1]} = $LOOP_ARRAY_REF_STACK[-1];
  }
  pop @LOOP_NAME_STACK;
}

sub TMPL_ITEM {
  $ITEM_HASH_REF_STACK[-1] = {};
}

sub TMPL_ITEM_ {
  push @{$LOOP_ARRAY_REF_STACK[-1]}, $ITEM_HASH_REF_STACK[-1];
}

sub Default {
  my ($p, $string) = @_;
  if(@LOOP_NAME_STACK){
    if($VAR_NAME){
      $ITEM_HASH_REF_STACK[-1]->{$VAR_NAME} .= $string;
    }
  } else {
    my $r = Apache->request;
    my $info = $info_hash{$r->dir_config("PKIT_PAGE_INFO_FILE")};
    if($ATTR_NAME){
      $info->{attr}->{$page_id}->{$ATTR_NAME} .= $string;
    } elsif($VAR_NAME){
      $info->{param}->{$page_id}->{$VAR_NAME} .= $string;
    }
  }
}

1;

=head1 NAME

Apache::PageKit::Info - Page attributes class

=head1 SYNOPSIS

This is class is a wrapper to the page attributes stored in the XML file
as specified by the Apache C<PKIT_PAGE_INFO_FILE> configuration directive.

=head1 METHODS

=over 4

=item get_attr

  $info->get_attr('use_nav', $page_id);

Gets the value of the C<use_nav> attribute of C<$page_id>.  The page_id argument is
optional, defaults to C<$pk-E<gt>{page_id}>.

=item get_param

  $info->get_param('html_title', $page_id);

Gets the CDATA in the C<E<lt>TMPL_VAR NAME="html_title"E<gt>> XML tag
of C<$page_id>.  The page_id argument is
optional, defaults to C<$pk-E<gt>{page_id}>.

=back

=head1 AUTHOR

T.J. Mather (tjmather@thoughtstore.com)

=head1 BUGS

Embeded <TMPL_LOOP>'s in the XML file have not been tested.

=head1 COPYRIGHT

Copyright (c) 2000, ThoughtStore, Inc.  All rights Reserved.  PageKit is a trademark
of ThoughtStore, Inc.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license
