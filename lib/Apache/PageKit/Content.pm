package Apache::PageKit::Content;

# $Id: Content.pm,v 1.21 2001/05/07 17:34:59 tjmather Exp $

use strict;

use vars qw($CONTENT $COMPONENT_ID_DIR $INCLUDE_MTIMES);

sub new($$) {
  my $class = shift;
  my $self = { @_ };
  bless $self, $class;
  return $self;
}

sub generate_template {
  my ($content, $type, $page_id, $component_id, $pkit_view, $input_param_obj) = @_;

  use XML::LibXML;
  use XML::LibXSLT;

  $CONTENT = $content;
  ($COMPONENT_ID_DIR = $component_id) =~ s![^/]*$!!;
  $INCLUDE_MTIMES = $content->{include_mtimes};

  # XSLT file
  my $xml_file = "$content->{content_dir}/$component_id.xml";
  unless(-e "$xml_file"){
    die "Cannot find xml file $content->{content_dir}/$component_id.xml or
      template file $pkit_view/$type/$component_id.tmpl";
  }

  my $xml_mtime = (stat($xml_file))[9];
  $INCLUDE_MTIMES->{$xml_file} = $xml_mtime;

  my $xp = XML::XPath->new(filename => $xml_file);
  my @pi_nodes = $xp->findnodes("processing-instruction('xml-stylesheet')");
  my @stylesheet_hrefs;
  for my $pi_node (@pi_nodes){
    my $pi_str = $pi_node->getData;
    my ($stylesheet_href) = ($pi_str =~ m!href="([^"]*)"!);
    push @stylesheet_hrefs, $stylesheet_href;
  }

  # for now, just use first stylesheet... we'll add multiple stylesheets later
  unless ($stylesheet_hrefs[0]){
    die qq{must specify <?xml-stylesheet href="file.xsl"?> in $xml_file};
  }
  my $stylesheet_file = "$content->{view_dir}/$pkit_view/XSL/$stylesheet_hrefs[0]";
  unless (-e "$stylesheet_file"){
    $stylesheet_file = "$content->{view_dir}/Default/XSL/$stylesheet_hrefs[0]";
    unless (-e "$stylesheet_file"){
      die qq{cannot find $stylesheet_hrefs[0] in $xml_file - looked in $stylesheet_file};
    }
  }

  my $stylesheet_mtime = (stat(_))[9];
  $INCLUDE_MTIMES->{$stylesheet_file} = $stylesheet_mtime;

  # for caching pages including the params info (that way extrenous parameters won't
  # be taken into account when counting)
  $xp = XML::XPath->new(filename => "$stylesheet_file");
  $Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id} = {};
  for my $node ($xp->findnodes(q{xsl:stylesheet/xsl:param})){
    my $param_name = $node->getAttribute('name');
    $Apache::PageKit::Content::PAGE_ID_XSL_PARAMS->{$page_id}->{$param_name} = 1;
  }

  my $parser = XML::LibXML->new(ext_ent_handler => \&open_uri);
  my $xslt = XML::LibXSLT->new();
  my $source = $parser->parse_file("$content->{content_dir}/$component_id.xml");
  my $style_doc = $parser->parse_file($stylesheet_file);

  my $stylesheet = $xslt->parse_stylesheet($style_doc);

  my @params = map { $_, $input_param_obj->param($_) } $input_param_obj->param ;

  my $results = $stylesheet->transform($source, @params);

  my $output = $stylesheet->output_string($results);

  return \$output;
}

sub process_template {
  my ($content, $component_id, $template_ref) = @_;

  my $lang_tmpl = {};
  $INCLUDE_MTIMES = {};

  if($$template_ref =~ m!<CONTENT_(VAR|LOOP|IF|UNLESS) !i){
    # XPathTemplate template

    my $xpt = XML::XPathTemplate->new(default_lang => $content->{default_lang},
					root_dir => $content->{content_dir});

    $lang_tmpl = $xpt->process_all_lang(xpt_scalarref => $template_ref,
					xml_filename => "$component_id.xml");
    my $file_mtimes = $xpt->file_mtimes;
    while (my ($k, $v) = each %$file_mtimes){
      $content->{include_mtimes}->{$k} = $v;
    }
  } else {
    $lang_tmpl->{$content->{default_lang}} = $template_ref;
  }
  return $lang_tmpl;
}

sub rel2abs {
  my ($rel_uri) = @_;
  my $content_dir = $CONTENT->{content_dir};
  if($rel_uri =~ m!^/!){
    return "$content_dir/$rel_uri";
  } else {
    # return relative to component_id_dir
    my $abs_uri = "$content_dir/$COMPONENT_ID_DIR$rel_uri";
    while ($abs_uri =~ s![^/]/\.\./!!) {};
    return $abs_uri;
  }
}

sub match_uri {
  my $uri = shift;
  return $uri !~ /^\w+:/;
}

sub open_uri {
  my $uri = shift;
  my $abs_uri = &rel2abs($uri);
  die "$abs_uri doesn't exist" unless (-e $abs_uri);
  open XML, "$abs_uri";
  local($/) = undef;
  my $xml_str = <XML>;
  close XML;
  my $mtime = (stat(_))[9];
  $INCLUDE_MTIMES->{$abs_uri} = $mtime;
  return $xml_str;
}

sub read_uri {
  return substr($_[0], 0, $_[1], "");
}

sub close_uri {}

# call backs so that we can note the mtimes of dependant files
XML::LibXML->match_callback(\&match_uri);
XML::LibXML->open_callback(\&open_uri);
XML::LibXML->close_callback(\&close_uri);
XML::LibXML->read_callback(\&read_uri);

1;
__END__

=head1 NAME

Apache::PageKit::Content - Adaptor to XML::LibXSLT and XML::XPathTemplate

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
