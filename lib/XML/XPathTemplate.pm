package XML::XPathTemplate;

use strict;
use XML::XPath;
use HTML::Template;

use Carp;

use vars qw($VERSION);
$VERSION = '0.03';

# public methods

sub new {
  my ($class, @options) = @_;
  my $self = { @options };
  bless $self, $class;
  $self->{'default_lang'} ||= 'en';
  return $self;
}

sub file_mtimes {
  return shift->{file_mtimes};
}

sub process {
  my ($xpt, %opt) = @_;

  # clear out data from preview call to process
  delete $xpt->{file_mtimes};
  delete $xpt->{lang};

  my $xpt_template_ref;

  if($opt{xpt_filename}){
    local($/) = undef;
    my $filename = "$xpt->{root_dir}/$opt{xpt_filename}";
    die "can't open $filename for reading"
      unless (-e "$filename");
    open XPT, "$filename";
    my $xpt_template = <XPT>;
    $xpt_template_ref = \$xpt_template;
    close XPT;
  } elsif ($opt{xpt_scalarref}){
    $xpt_template_ref = $opt{xpt_scalarref};
  }

  $opt{lang} ||= $xpt->{default_lang};

  $$xpt_template_ref =~ s!<CONTENT_VAR!<TMPL_VAR!ig;
  $$xpt_template_ref =~ s!<CONTENT_LOOP!<TMPL_LOOP!ig;
  $$xpt_template_ref =~ s!</CONTENT_VAR!</TMPL_VAR!ig;
  $$xpt_template_ref =~ s!</CONTENT_LOOP!</TMPL_LOOP!ig;

  $xpt->_fill_in_content($xpt_template_ref, $opt{xml_filename}, $opt{lang}, $opt{check_for_other_lang});

  return $xpt->{lang}->{$opt{lang}};
}

sub process_all_lang {
  my ($xpt, %opt) = @_;
  $opt{check_for_other_lang} = 1;
  $xpt->process(%opt);

  return $xpt->{lang};
}

# private methods

sub _add_content_mtime {
  my ($xpt, $xml_filename) = @_;
  my $filename = "$xpt->{root_dir}/$xml_filename";
  return if exists $xpt->{file_mtimes}->{$filename};
  my $mtime = (stat($filename))[9];
  $xpt->{file_mtimes}->{$filename} = $mtime;
}

sub _fill_in_content {
  my ($xpt, $xpt_template_ref, $default_xml_filename, $lang, $check_for_other_lang) = @_;

  $xpt->{language_parsed}->{$lang} = 1;

  my $tmpl;
  eval {
    $tmpl = HTML::Template->new(scalarref => $xpt_template_ref,
				   # don't die when we set a parameter that is not in the template
				   die_on_bad_params=>0,
				   # built in __FIRST__, __LAST__, etc vars
				   loop_context_vars=>1,
				   case_sensitive=>1,
				   max_includes => 50);
  };
  if($@){
    die "Can't load template (preprocessing): $@";
  }

  my @params = $tmpl->query;
  for my $name (@params){
#    next unless $name =~ m!^pkit_content::!;
    my $type = $tmpl->query(name => $name);
    my ($xml_filename, $xpath) = $xpt->_get_document_xpath($name,$default_xml_filename);
    $xpt->_add_content_mtime($xml_filename);
    my $value;
    if($type eq 'LOOP'){
      $value = $xpt->_fill_in_content_loop($xpt_template_ref, $default_xml_filename, $tmpl, $xml_filename, $lang, [ $name ], $check_for_other_lang);
    } else {
      if($check_for_other_lang){
	my $langs = $xpt->_get_xpath_langs(xml_filename => $xml_filename,
					   xpath => $xpath);
	for my $l (@$langs){
	  $xpt->_fill_in_content($xpt_template_ref, $default_xml_filename, $l, 0)
	    unless exists $xpt->{language_parsed}->{$l};
	}
      }
      my $nodeset = $xpt->_get_xpath_nodeset(xml_filename => $xml_filename,
					     xpath => $xpath,
					     lang => $lang);

      # get value of first node
      $value = $nodeset->string_value;

      # XML::Parser outputs as utf8, so we convert to latin1 to deal
      # with accented characters in french, german, etc
      if($lang ne 'en' && exists $INC{'Unicode/String.pm'}){
	$value = Unicode::String::utf8($value)->latin1 unless $lang eq 'en';
      }
    }
    $tmpl->param($name => $value);
  }
  # html, filtered for content
  $xpt->{lang}->{$lang} = \$tmpl->output;
}

sub _fill_in_content_loop {
  my ($xpt, $xpt_template_ref, $default_xml_filename, $tmpl,
  $context_xml_filename, $lang, $loops, $check_for_other_lang, $context) = @_;

  my ($xpath) = ($xpt->_get_document_xpath($loops->[-1],$default_xml_filename))[1];

  my @inner_param_names = $tmpl->query(loop => $loops);
  my %inner_param;
  for my $name (@inner_param_names){
    my ($xml_filename, $xpath) = $xpt->_get_document_xpath($name,$default_xml_filename);
    $xpt->_add_content_mtime($xml_filename);
    $inner_param{$name} = {type => $tmpl->query(name => [ @$loops, $name ]),
			   xml_filename => $xml_filename,
			   xpath => $xpath};
  }

  my $nodeset = $xpt->_get_xpath_nodeset(xml_filename => $context_xml_filename,
					 xpath => $xpath,
					 lang => $lang,
					 context => $context);

  my $array_ref = [];

  for my $node ($nodeset->get_nodelist){
    my $loop_param = {};
    while (my ($name, $hash_ref) = each %inner_param){
      my $value;
      my $context = $node;
      if($hash_ref->{type} eq 'LOOP'){
	$value = $xpt->_fill_in_content_loop($xpt_template_ref, $default_xml_filename, $tmpl, $hash_ref->{xml_filename}, $lang, [ @$loops, $name], $check_for_other_lang, $node);
      } else {
	if($check_for_other_lang){
	  my $langs = $xpt->_get_xpath_langs(xml_filename => $hash_ref->{xml_filename},
					     xpath => $hash_ref->{xpath},
					     context => $context);
	  for my $l (@$langs){
	    $xpt->_fill_in_content($xpt_template_ref, $default_xml_filename, $l, 0)
	      unless exists $xpt->{language_parsed}->{$l};
	  }
	}
	my $nodeset = $xpt->_get_xpath_nodeset(xml_filename => $hash_ref->{xml_filename},
					       xpath => $hash_ref->{xpath},
					       lang => $lang,
					       context => $context);
	# get value of first node
	$value = $nodeset->string_value;
      }
      $loop_param->{"$name"} = $value;
    }
    push @$array_ref, $loop_param;
  }
  return $array_ref;
}

sub _get_document_xpath {
  my ($xpt, $name, $default_xml_filename) = @_;
  my ($xml_filename, $xpath);
  if($name =~ m!^document\('?(.*?)'?\)(.*)$!){
    ($xml_filename, $xpath) = ($1, $2);
    unless($xml_filename =~ s!^/!!){
      # return relative to $default_xml_filename
      (my $default_xml_dir = $default_xml_filename) =~ s![^/]*$!!;
      $xml_filename = "$default_xml_dir$xml_filename";
      while ($xml_filename =~ s![^/]*/\.\./!!) {};
    }
  } else {
    ($xml_filename, $xpath) = ($default_xml_filename, $name);
  }
  return ($xml_filename, $xpath);
}

sub _get_xp {
  my ($xpt, $xml_filename) = @_;

  if(exists $xpt->{xp}->{$xml_filename}){
    return $xpt->{xp}->{$xml_filename};
  } else {
    my $filename = "$xpt->{root_dir}/$xml_filename";
#    die "Can't load $filename" unless
#      (-e "$filename");
#    die "Can't load content file $filename" unless
#      (-e "$filename");
    unless (-e "$filename"){
      warn "Can't load content file $filename";
      return;
    }
    my $xp = XML::XPath->new(filename => "$filename");

    # get default context (root XML element)
    $xpt->{root_element_node}->{$xml_filename} = $xp->findnodes("/*")->[0];

    $xpt->{xp}->{$xml_filename} = $xp;
    return $xp;
  }
}

sub _get_xpath_langs {
  my ($xpt, %arg) = @_;

  my $xml_filename = $arg{xml_filename};
  my $xp = $xpt->_get_xp($xml_filename);
  return [] unless $xp;

  my $xpath = $arg{xpath};
  my $context = $arg{context} || $xpt->{root_element_node}->{$xml_filename};

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

sub _get_xpath_nodeset {
  my ($xpt, %arg) = @_;

  my $xml_filename = $arg{xml_filename};

  my $return_nodeset = XML::XPath::NodeSet->new;
  my $xp = $xpt->_get_xp($xml_filename);
  return $return_nodeset unless $xp;
  my $xpath = $arg{xpath};
  my $lang = $arg{lang};
  my $context = $arg{context} || $xpt->{root_element_node}->{$xml_filename};

  my $nodeset = $xp->find($xpath, $context);
  my @nodelist = $nodeset->get_nodelist;

  # first attempt get nodes whose ancestor-or-self[@xml:lang] eq $lang
  for my $node (@nodelist) {
    # lifted from XPath::Function::lang
    my $node_lang = $node->findvalue('(ancestor-or-self::*[@xml:lang]/@xml:lang)[last()]') || $xpt->{default_lang};
    if (substr(lc($node_lang), 0, length($lang)) eq $lang) {
      $return_nodeset->push($node);
    }
  }
  return $return_nodeset if $return_nodeset->size > 0;

  # If no nodes are found in the preferred language, then return
  # node(s) which are in the default language
  for my $node (@nodelist) {
    my $node_lang = $node->findvalue('(ancestor-or-self::*[@xml:lang]/@xml:lang)[last()]') || $xpt->{default_lang};
    if (substr(lc($node_lang), 0, length($xpt->{default_lang})) eq $xpt->{default_lang}) {
      $return_nodeset->push($node);
    }
  }
  return $return_nodeset if $return_nodeset->size > 0;

  # pass 3, just return all the nodes
  # (even thought it's not in the right language)
  # this is undocumented and subject to change!
  return $nodeset;
}

1;

__END__

=head1 NAME

XML::XPathTemplate - Easy access to XML files using XPath and HTML::Template

=head1 SYNOPSIS

In your perl code:

  my $xpt = new XML::XPathTemplate(default_lang => 'en',
				  root_dir = $root_dir);

  my $output = $xpt->process(xpt_filename => $xpt_filename,
			     xml_filename => $xml_filename,
			     lang => 'en');

  # hash references containing filenames and mtimes, used by PageKit for
  # caching
  my $file_mtimes = $xpt->file_mtimes;

Your XPathTemplate template:

  Header
  <CONTENT_VAR NAME="document('foo.xml')/aaa/bbb">
  <CONTENT_VAR NAME="/ddd/aaa/@bbb">
  <CONTENT_VAR NAME="/ddd/eee">
  <CONTENT_VAR NAME="eee">
  <CONTENT_LOOP NAME="/ddd/fff">
        <CONTENT_VAR NAME="@ttt">
        <CONTENT_VAR NAME="ggg">
        <CONTENT_VAR NAME="hhh"> <CONTENT_VAR NAME="hhh/@qqq">
        <CONTENT_VAR NAME="iii">
  </CONTENT_LOOP>
  Footer

Your XML file:

  <ddd>
  <aaa bbb="ccc"/>
        <eee>jjj</eee>
        <fff ttt="uuu">
                <ggg>sss</ggg>
                <hhh qqq="rrr">lll</hhh>
                <iii>mmm</iii>
        </fff>
        <fff ttt="vvv">
                <ggg>nnn</ggg>
                <hhh>ooo</hhh>
                <iii>ppp</iii>
        </fff>
  </ddd>

Second XML file (foo.xml)

  <aaa>
    <bbb>Content from second XML file</bbb>
  </aaa>

Output:

  Header
  Content from second XML file
  ccc
  jjj
  jjj

        uuu
        sss
        lll rrr
        mmm
 
        vvv
        nnn
        ooo
        ppp

  Footer

=head1 DESCRIPTION

This is an easy to use templating system for extracting content from XML
files.  It is based on <HTML::Template>'s <TMPL_VAR> and <TMPL_LOOP> tags
and uses L<XML::XPath> to extract the requested XML content.

It has built-in support for language localization.

=head1 METHODS

=over 4

=item process_all_lang

Processes the template and returns a hash reference containing language
codes as keys and outputs as values.

  my $lang_output = $xpt->process_all_lang(filename => $filename);

  # english output
  my $output_en = $lang_output->{'en'};

=back

=head1 AUTHOR

T.J. Mather (tjmather@anidea.com)

=head1 BUGS

If you use the same XPath query for a CONTENT_LOOP as well as a CONTENT_VAR
tag, then HTML::Template will croak.  A workaround is to append a "/." at
the end of the xpath query.

=head1 COPYRIGHT

Copyright (c) 2000, 2001 AnIdea Corporation.  All rights Reserved.  PageKit is a trademark
of AnIdea Corporation.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
