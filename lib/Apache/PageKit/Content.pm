package Apache::PageKit::Content;

# $Id: Content.pm,v 1.16 2001/04/25 22:06:39 tjmather Exp $

# How content will work:

# all content paramater names will be XPath queries
# all content tags will get compiled
# 1. $template->query is called for every "content:" variable
# 2. xpath query is evaluated

# HOW will CONTENT_LOOP work?

# new functions:

# Apache::PageKit::Content->new($content_dir, $default_lang);
# $content->get_languages($content_id);
# $content->get_xpath_nodeset($content_id, $xpath, [$lang], [$context]);
#   if lang=default_lang
#     then no ancestor-or-self node should have node=other_lang with its sister
#     has a node=lang or node not set
#   else 
#     then no ancestor node should have node=other_lang when its sister
#     has a node=lang
#### $content->get_xpath_nodeset($content_id, $xpath, [$lang], [$context]);

use strict;
use XML::XPath;

sub new {
  my ($class, @options) = @_;
  my $self = { @options };
  bless $self, $class;
  $self->{'default_lang'} ||= 'en';
  return $self;
}

# used by Apache::PageKit::View for caching
sub get_filename {
  my ($content, $content_id) = @_;
  return "$content->{content_dir}/$content_id.xml";
}

sub _get_xp {
  my ($content, $content_id) = @_;

  if(exists $content->{xp}->{$content_id}){
    return $content->{xp}->{$content_id};
  } else {
    my $filename = "$content->{content_dir}/$content_id.xml";
    die "Can't load $filename" unless
      (-e "$filename");
    my $xp = XML::XPath->new(filename => "$filename");

    # get default context (root XML element)
    $content->{root_element_node}->{$content_id} = $xp->findnodes("/*")->[0];

    $content->{xp}->{$content_id} = $xp;
    return $xp;
  }
}

sub get_languages ($$) {
  my ($content, $content_id) = @_;

  my $xp = $content->_get_xp($content_id);

  my $nodeset = $xp->find('//*[@xml:lang]');

  my %lang = ();

  for my $node ($nodeset->get_nodelist) {
    my $lang = $node->getAttribute('xml:lang');
    $lang{$lang} = 1;
  }
  my @lang = keys %lang;
  return \@lang;
}

sub get_xpath_langs {
  my ($content, %arg) = @_;

  my $content_id = $arg{content_id};
  my $xp = $content->_get_xp($content_id);

  my $xpath = $arg{xpath};
  my $context = $arg{context} || $content->{root_element_node}->{$content_id};

  my $nodeset = $xp->find($xpath, $context);

  my %lang;

  my $return_nodeset = XML::XPath::NodeSet->new;

  for my $node ($nodeset->get_nodelist) {
    my $nodeset = $xp->find(q{ancestor-or-self::*[@xml:lang]},$node);
    for my $node ($nodeset->get_nodelist) {
      my $lang = $node->getAttribute('xml:lang');
      $lang{$lang} = 1;
    }
    $return_nodeset->push($node) if $nodeset->size > 0;
  }
  my @lang = keys %lang;
  return \@lang;
}

sub get_xpath_nodeset {
  my ($content, %arg) = @_;

  my $content_id = $arg{content_id};
  my $xp = $content->_get_xp($content_id);
  my $xpath = $arg{xpath};
  my $lang = $arg{lang};
  my $context = $arg{context} || $content->{root_element_node}->{$content_id};

  my $nodeset = $xp->find($xpath, $context);
  my @nodelist = $nodeset->get_nodelist;

  my $return_nodeset = XML::XPath::NodeSet->new;

  # pass 1, return node that has matching xml:lang tag
  for my $node (@nodelist) {
    my $node_lang = $node->getAttribute('xml:lang');
    $return_nodeset->push($node) if $node_lang eq $lang ||
      (!$node_lang && $lang eq $content->{default_lang});
  }
  return $return_nodeset if $return_nodeset->size > 0;

  # pass 2, return node that has ancestor with matching xml:lang tag
  for my $node (@nodelist) {
    my @nodes = $xp->findnodes(qq{ancestor::*[\@xml:lang = "$lang"]},$node);
    $return_nodeset->push($node) if @nodes;
  }
  return $return_nodeset if $return_nodeset->size > 0;

  # pass 3, return nodes in default language (better than all languages)
  for my $node (@nodelist) {
    my $node_lang = $node->getAttribute('xml:lang');
    $return_nodeset->push($node) if $node_lang eq $content->{default_lang} ||
      !$node_lang;
  }
  return $return_nodeset if $return_nodeset->size > 0;

  # pass 4, just return all the nodes
  # (even thought it's not in the right language)
  return $nodeset;
}

1;
