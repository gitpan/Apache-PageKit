package Apache::PageKit::Info;

# $Id: Info.pm,v 1.13 2000/08/24 19:21:53 tjmather Exp $

use integer;
use strict;

sub new {
  my ($class) = @_;
  my $self = {};
  bless $self, $class;
  $self->_init(@_);
  return $self;
}

sub _init {
  my ($info) = @_;

  # delete current init
  $info->{page_id_match} = {};

  my $r = Apache->request;

  my $page_info_file = $r->dir_config("PKIT_PAGE_INFO_FILE");

  open PAGEINFO, "$page_info_file";
  $_ = <PAGEINFO>;

  chomp;
  s/\r$//;
  s/\s+$//;
  my @header = split("\t",$_);
  $info->{avail_param} = \@header;
  my %header_index;
  for (my $i = 0; $i < @header; $i++){
    $header_index{$header[$i]} = $i;
  }

  while(<PAGEINFO>){
    chomp;
    s/\r$//;
    my @row = split("\t",$_);

    #get rid of quotes put in by microsoft excel
    for(my $i = 0; $i < @row; $i++){
      $row[$i] =~ s/^"(.*)"$/$1/;
    }

    my $page_id = $row[$header_index{'page_id'}];
    my $domain = $row[$header_index{'domain'}];
    if((my $sub_domain = $r->dir_config('PKIT_SUBDOMAIN')) && $domain){
      $domain =~ s/([^.]*)\.([^.]*)$/$sub_domain.$1.$2/;
      $row[$header_index{'domain'}] = $domain;
    }

    for(my $i = 0; $i < @row; $i++){
      next if $header[$i] eq 'page_id';
      if($header[$i] eq 'page_id_match'){
	$info->{page_id_match}->{$page_id} = $row[$i] if $row[$i];
      } else {
	$info->{info}->{$page_id}->{$header[$i]} = $row[$i];
	if($header[$i] eq 'is_topdomain' && $row[$i] eq 'yes'){
	  $info->{domain}->{$domain} = $page_id;
	}
      }
    }
  }
  close PAGEINFO;
  Apache::PageKit->call_plugins($info, 'info_init_handler');
}

sub associate_pagekit {
  my ($info, $pk) = @_;

  # used by the param method to get the page_id
  $info->{pk} = $pk;

  my $r = Apache->request;

  # on production, we don't check for new page file
  return $info if $r->dir_config('PKIT_PRODUCTION') eq 'on';

  my $page_info_file = $r->dir_config("PKIT_PAGE_INFO_FILE");

  my $mtime = (stat $page_info_file)[9];
  if($mtime > $Apache::PageKit::Info::pageMtime{$r->dir_config("PKIT_PAGE_INFO_FILE")}){
    $info->_init;
    $Apache::PageKit::Info::pageMtime{$r->dir_config("PKIT_PAGE_INFO_FILE")} = $mtime;
  }
  return $info;
}

sub page_exists {
  my ($info, $page_id) = @_;
  if (exists $info->{info}->{$page_id}){
    return 1;
  } else {
    return 0;
  }
}

sub avail_param {
  my ($info) = @_;
  return @{$info->{avail_param}};
}

# optional page_id paramater
sub get_param {
  my ($info, $attr, $page_id) = @_;
  return unless $info->{pk};
  $page_id ||= $info->{pk}->{page_id};
  return unless $info->{info}->{$page_id};
  return $info->{info}->{$page_id}->{$attr};
}

# optional page_id paramater
sub set_param {
  my ($info, $attr, $value, $page_id) = @_;
  return unless $info->{pk};
  $page_id ||= $info->{pk}->{page_id};
  $info->{info}->{$page_id}->{$attr} = $value;
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
1;

=head1 NAME

Apache::PageKit::Info - Page attributes class

=head1 DESCRIPTION

This is class is a wrapper to the page attributes stored in the file
as specified by the Apache C<PKIT_PAGE_INFO_FILE> configuration directive.

=head1 METHODS

=over 4

=item get_param

  $info->get_param('use_nav', $page_id);

Gets the value of the C<use_nav> attribute of C<$page_id>.  The page_id is
optional, defaults to C<$pk-E<gt>{page_id}>.

=back

=head1 AUTHOR

T.J. Mather (tjmather@thoughtstore.com)

=head1 COPYRIGHT

Copyright (c) 2000, ThoughtStore, Inc.  All rights Reserved

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license
