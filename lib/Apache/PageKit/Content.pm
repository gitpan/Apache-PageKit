package Apache::PageKit::Content;

# $Id: Content.pm,v 1.4 2000/12/23 07:10:38 tjmather Exp $

use strict;
use XML::Parser ();
use Storable ();

use vars qw($VAR_NAME $VAR_NEW $mtime_hashref
	@LOOP_NAME_STACK @ITEM_HASH_REF_STACK $memory_cache $page_cache
	@LOOP_ARRAY_REF_STACK $xml_lang $PARAM_HASH $default_lang);

sub new {
  my ($class, %options) = @_;
  my $self = {%options};
  bless $self, $class;
  $self->_init;
  return $self;
}

sub _init{
  my ($content) = @_;
  $content->{reload} ||= 'yes';
  $default_lang = $content->{default_lang} || 'en';
  my $lang_arrayref = [];
  for my $lang (@{$content->{lang_arrayref}}){
    push @$lang_arrayref, $lang;
    last if $lang eq $default_lang;
  }
  # add default language as a backup unless already on stack
  push @$lang_arrayref, $default_lang unless scalar(@$lang_arrayref) && $lang_arrayref->[-1] eq $default_lang;
  $content->{lang_arrayref} = $lang_arrayref;
}

# should be called after Config.xml is read
sub parse_all {
  my ($content) = @_;

  $default_lang = $content->{default_lang};

  # clean up old content cache files
  $content->cleanup;

  # find files in content_root/xml directory
  opendir XML, "$content->{content_dir}/xml";

  my @page_ids = map { m/^(.*)\.xml$/ } readdir XML;
  closedir XML;

  # make sure cache dir exists
  mkdir "$content->{content_dir}/cache",0755 unless (-d "$content->{content_dir}/cache");

  # parse XML files
  for my $page_id (@page_ids){
    $content->parse_page($page_id);
  }
}

# removes files from cache
sub cleanup {
  my ($content) = @_;

  opendir CACHE, "$content->{content_dir}/cache";
  my @files = grep !/^\.\.?$/, readdir CACHE;
  for (@files){
    unlink "$content->{content_dir}/cache/$_";
  }
  closedir CACHE;
}

sub parse_page {
  my ($content, $page_id) = @_;

  $PARAM_HASH = {};

  # set up parser
  my $p = XML::Parser->new(Style => 'Subs',
			   ParseParamEnt => 1,
			   NoLWP => 1);

  $p->setHandlers(Default => \&Default);
  $p->parsefile("$content->{content_dir}/xml/$page_id.xml");

  if($content->{reload} eq 'yes'){
    # store information about last modified date of file for reloading purposes
    $mtime_hashref->{$page_id} = (stat "$content->{content_dir}/xml/$page_id.xml")[9];
  }

  # dump content from %PARAM_HASH into cache files for each page and language
  for my $lang (keys %$PARAM_HASH){
    # check to see if we cache content in memory or in file
    # $page_cache is set by the PAGE sub that gets called for the <PAGE cache="yes"> tag
    if($page_cache eq 'yes' || ($page_cache eq 'default' && $lang eq $default_lang)){
      # cache is set to yes or default (and lang is the default)
      # so we store the content in $memory_cache
      $memory_cache->{$page_id}->{$lang} = $PARAM_HASH->{$lang};
    } else {
      # just store navigation information (since it is accessed most frequently)
      $memory_cache->{$page_id}->{$lang}->{pkit_nav_title} =
	$PARAM_HASH->{$lang}->{pkit_nav_title} if
	  exists $PARAM_HASH->{$lang}->{pkit_nav_title};
      # set flag indicating that rest of params are stored in file_cache
      $memory_cache->{$page_id}->{$lang}->{pkit_file_cache} = 1;
    }
    # store in file as well
    Storable::store $PARAM_HASH->{$lang}, "$content->{content_dir}/cache/$page_id.$lang.dat";
  }
}

sub _check_for_reload {
  my ($content, $page_id) = @_;

  # check to see if content xml file has been updated
  my $mtime = (stat "$content->{content_dir}/xml/$page_id.xml")[9];
  if($mtime > $mtime_hashref->{$page_id}){
    # xml file has been updated, re-parse
    $content->parse_page($page_id);
  }
}

# for optimal results, should be called after get_param_hashref
sub get_param {
  my ($content, $page_id, $key) = @_;

  $key = "content:" .$key;

  # first check to see if arrayref has already been requested
  my $value;
  if(exists $content->{memory_cache}->{$page_id} &&
	($value = $content->{memory_cache}->{$page_id}->{$key})){
    return $value;
  }

  $content->_check_for_reload($page_id) if $content->{reload} eq 'yes';

  # iterate through available languages
  for my $lang (reverse @{$content->{lang_arrayref}}){
    if($value = $memory_cache->{$page_id}->{$lang}->{$key}){
      # first check server process memory
      return $value;
    } elsif (-e "$content->{content_dir}/cache/$page_id.$lang.dat"){
      # if not in memory, attempt to load from file
      my $h2 = Storable::retrieve("$content->{content_dir}/cache/$page_id.$lang.dat");
      return $h2->{$key};
    }
  }
}

sub get_param_hashref {
  my ($content, $page_id) = @_;

  # first check to see if arrayref has already been requested
  if(my $param_hashref = $content->{memory_cache}->{$page_id}){
    return $param_hashref;
  }

  $content->_check_for_reload($page_id) if $content->{reload} eq 'yes';

  # iterate through available languages
  my $param_hashref = {};
  for my $lang (reverse @{$content->{lang_arrayref}}){
    if(my $h = $memory_cache->{$page_id}->{$lang} &&
	not exists $memory_cache->{$page_id}->{$lang}->{pkit_file_cache}){
      # first check server process memory
      while(my ($k, $v) = each %$h){
        $param_hashref->{$k} = $h->{$k};
      }
    } elsif (-e "$content->{content_dir}/cache/$page_id.$lang.dat"){
      # if not in memory, attempt to load from file
      my $h2 = Storable::retrieve("$content->{content_dir}/cache/$page_id.$lang.dat");
      while(my ($k, $v) = each %$h2){
        $param_hashref->{$k} = $h2->{$k};
      }
    }
  }
  # cache for rest of request cycle
  $content->{memory_cache}->{$page_id} = $param_hashref;
  return $param_hashref;
}

sub PAGE {
  my ($p, $edtype, %attr) = @_;
  $page_cache = $attr{cache} || 'no';
}

sub NAV_TITLE {
  my ($p, $edtype, %attr) = @_;

  $VAR_NAME = 'pkit_nav_title';

  $xml_lang = $attr{'xml:lang'};
  # if langauge is not specified, choose default language
  $xml_lang ||= $default_lang;
}

sub NAV_TITLE_ {
  $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/^<!\[CDATA\[//g;
  $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/\]\]>$//g;
  $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/\s+/ /g;
  $xml_lang = undef;

  $VAR_NAME = undef;
  $VAR_NEW = 1;
}

sub CONTENT_VAR {
  my ($p, $edtype, %attr) = @_;

  $VAR_NAME = $attr{NAME};

  $xml_lang = $attr{'xml:lang'};
  # if langauge is not specified, choose default language
  $xml_lang ||= $default_lang;
}

sub CONTENT_VAR_ {

  if(@LOOP_NAME_STACK){
    if($VAR_NAME){
      $ITEM_HASH_REF_STACK[-1]->{"content:". $VAR_NAME} =~ s/^<!\[CDATA\[//g;
      $ITEM_HASH_REF_STACK[-1]->{"content:". $VAR_NAME} =~ s/\]\]>$//g;
      $ITEM_HASH_REF_STACK[-1]->{"content:". $VAR_NAME} =~ s/\s+/ /g;
    }
  } else {
    $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/^<!\[CDATA\[//g;
    $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/\]\]>$//g;
    $PARAM_HASH->{$xml_lang}->{"content:". $VAR_NAME} =~ s/\s+/ /g;
    $xml_lang = undef;
  }

  $VAR_NAME = undef;
  $VAR_NEW = 1;
}

sub CONTENT_LOOP {
  my ($p, $edtype, %attr) = @_;

  # set language iff top level loop
  unless (@LOOP_NAME_STACK){
    $xml_lang = $attr{'xml:lang'};
    # if langauge is not specified, choose default language
    $xml_lang ||= $default_lang;
  }

  push @LOOP_NAME_STACK, $attr{NAME};
  push @LOOP_ARRAY_REF_STACK, [];
  push @ITEM_HASH_REF_STACK, {};
}

sub CONTENT_LOOP_ {
  if(scalar @LOOP_NAME_STACK == 1){
    $PARAM_HASH->{$xml_lang}->{"content:" . $LOOP_NAME_STACK[0]} = $LOOP_ARRAY_REF_STACK[-1];
  } else {
    # nested LOOP element
    $ITEM_HASH_REF_STACK[-2]->{"content:" . $LOOP_NAME_STACK[-1]} = $LOOP_ARRAY_REF_STACK[-1];
  }
  pop @LOOP_NAME_STACK;
}

sub CONTENT_ITEM {
  $ITEM_HASH_REF_STACK[-1] = {};
}

sub CONTENT_ITEM_ {
  push @{$LOOP_ARRAY_REF_STACK[-1]}, $ITEM_HASH_REF_STACK[-1];
}

sub Default {
  my ($p, $string) = @_;
  return unless $VAR_NAME;
  if(@LOOP_NAME_STACK){
    if($VAR_NAME){
      $ITEM_HASH_REF_STACK[-1]->{"content:" . $VAR_NAME} .= $string;
    }
  } else {
    if($VAR_NEW){
      $PARAM_HASH->{$xml_lang}->{"content:" . $VAR_NAME} = $string;
      $VAR_NEW = 0;
    } else {
      $PARAM_HASH->{$xml_lang}->{"content:" . $VAR_NAME} .= $string;
    }
  }
}

1;
__END__

=head1 NAME

Apache::PageKit::Content - Parses and stores content in XML files.

=head1 DESCRIPTION

The module loads data from XML files stored in the Content/XML directory
under the PageKit root directory.  Upon server startup, it parses
the XML files and stores the data structures in Content/Cache directory.
It then loads the data from the cache when a page is requested.

=head1 SYNOPSIS

Load content into cache, called when web server starts.

  my $content = Apache::PageKit::Content->new(content_dir => $content_dir,
					default_lang => $default_lang,
					reload => 'yes');
  $content->parse_all;

Load content from cache into view object.

  my $content = Apache::PageKit::Content->new(content_dir => $content_dir,
					default_lang => $default_lang,
					lang_arrayref => $lang_arrayref,
					reload => 'yes');
  my $param_hashref = $content->get_param_hashref($page_id, $iso_lang);

=head1 METHODS

The following methods are available to the user:

=over 4

=item parse_all

Load content into cache, called when web server starts.

  my $content = Apache::PageKit::Content->new(content_dir => $content_dir,
					default_lang => $default_lang,
					reload => 'yes');
  $content->parse_all;

=item get_param_hashref

Load content from cache, returns hash reference containing parameters
that can be loaded into HTML::Template.

  my $content = Apache::PageKit::Content->new(content_dir => $content_dir,
					default_lang => $default_lang,
					lang_arrayref => $lang_arrayref,
					reload => 'yes');
  my $param_hashref = $content->get_param_hashref($page_id, $iso_lang);

=head1 XML Tags

The following tags are allowed in the Content XML files:

=over 4

=item <PAGE>

This tag contains <CONTENT_VAR> and <CONTENT_LOOP> tags for the content
of the page specified by <I>id</I>.

  <PAGE id="welcome" cache="yes">
    <CONTENT_VAR NAME="title" xml:lang="en">Title in English</CONTENT_VAR>
  </PAGE>

If the <I>cache</I> attribute is set to <I>yes</I>, then content will be stored
in memory instead of a cache file for all languages.  If <I>cache</I>
is set to <I>default</I>, then the content will be stored in memory for
the default application.  The default setting for <I>cache</I> is
<I>no</i>, which stores the content in cache files.

=item <CONTENT_VAR>

Corresponds to <CONTENT_VAR> tag in HTML::Template file.

  <CONTENT_VAR NAME="title" xml:lang="en"><![CDATA[Title in English]]></CONTENT_VAR>
  <CONTENT_VAR NAME="title" xml:lang="es"><![CDATA[Titulo en Espanol]]></CONTENT_VAR>

=item <CONTENT_ITEM> and <CONTENT_LOOP>

Corresponds to <CONTENT_LOOP> tag in HTML::Template file.

  <CONTENT_LOOP NAME="news">
    <CONTENT_ITEM>
      <CONTENT_VAR NAME = "date">August 28th, 2000</CONTENT_VAR>
      <CONTENT_VAR NAME = "title">Release of PageKit 0.02</CONTENT_VAR>
      <CONTENT_VAR NAME = "description">Added XML support for attributes and content</CONTENT_VAR>
    </CONTENT_ITEM>
    <CONTENT_ITEM>
      <CONTENT_VAR NAME = "date">August 24th, 2000</CONTENT_VAR>
      <CONTENT_VAR NAME = "title">Release of PageKit 0.01</CONTENT_VAR>
      <CONTENT_VAR NAME = "description">Initial Release</CONTENT_VAR>
    </CONTENT_ITEM>
  </CONTENT_LOOP>

This example is from the content file for the front page of the
pagekit website at http://www.pagekit.org/

=back

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 BUGS

Embeded <CONTENT_LOOP>'s in the XML file have not been tested.

=head1 COPYRIGHT

Copyright (c) 2000, AnIdea Corporation.  All rights Reserved.
PageKit is a trademark of AnIdea Corporation.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
