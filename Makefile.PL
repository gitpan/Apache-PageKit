
#
#
#

package MY;
sub postamble {
  return <<'ENDE';
patch_blib: pm_to_blib
	test "$(PERLRUN_VERSION_GE_58)" && ( cd blib; $(PATCH)  -V never -Elp1 <../patch_file.diff )
	@$(TOUCH) $@

ENDE
}

sub tools_other {
  my $t = shift->SUPER::tools_other(@_);
  $t .= "PATCH = patch\n";
  $t .= "PERLRUN_VERSION_GE_58 = " . ( $] >= 5.008 ) . "\n";
  $t;
}

sub top_targets {
  my $t = shift->SUPER::top_targets(@_);
  if ( $] >= 5.008 ) {
    $t =~ s!pure_all :: config pm_to_blib!pure_all :: config patch_blib!;
  }
  $t;
}
1;


#
# write the diff. so it can be easy removed from cvs one day.
#

package main;
open FH, ">patch_file.diff" || die $!;
print FH <<'__THIS_IS_THE_END__';
diff -Nur a/lib/Apache/PageKit/Model.pm b/lib/Apache/PageKit/Model.pm
--- a/lib/Apache/PageKit/Model.pm	2004-03-12 10:15:16.000000000 +0100
+++ b/lib/Apache/PageKit/Model.pm	2004-03-12 10:15:28.000000000 +0100
@@ -204,15 +204,8 @@
   # translate from default_input_charset to default_output_charset if needed
   my $view = $model->{pkit_pk}->{view};
   my $input_charset = $view->{default_input_charset};
-  my $default_output_charset = $view->{default_output_charset};
-  if ($input_charset ne $default_output_charset) {
-    my $converter = eval { Text::Iconv->new($input_charset, $default_output_charset) };
-    if ($@) {
-      die "Charset $input_charset or $default_output_charset not supported by Text::Iconv";
-    }
-    $message = $converter->convert($message) || die "Can not convert page from $input_charset to $default_output_charset" if $message;
-  }
-
+  $message = Encode::decode($input_charset, $message );
+  
   my $default_error_str = $model->pkit_get_config_attr( GLOBAL => 'default_errorstr' ) || "#ff0000";
   $message  =~ s/<(!--)?\s*PKIT_ERRORSTR\s*(?(1)--)>/$default_error_str/gi;
 
@@ -290,7 +283,12 @@
 }
 
 sub fillinform {
-  return shift->{pkit_pk}->{fillinform_object}->param(@_);
+  my $model = shift;
+  my @params = @_;
+  for ( @params ) {
+    Encode::_utf8_off( $_ ) unless ref $_;
+  }
+  return $model->{pkit_pk}->{fillinform_object}->param(@params);
 }
 
 sub ignore_fillinform_fields {
@@ -313,17 +311,7 @@
   my ($model, %p) = @_;
   my $view = $model->{pkit_pk}->{view};
   my $input_charset = exists $p{input_charset} ? $p{input_charset} : $view->{default_input_charset};
-  my $default_output_charset = $view->{default_output_charset};
-  if ($input_charset ne $default_output_charset) {
-    my $converter;
-    eval {
-      $converter = Text::Iconv->new($input_charset, $default_output_charset);
-    };
-    if ($@) {
-      die "Charset $input_charset or $default_output_charset not supported by Text::Iconv";
-    }
-    &_change_params($converter, $p{output} ? %{$p{output}} : %p );
-  }
+    &_change_params($input_charset, $p{output} ? %{$p{output}} : %p );
   $model->output( $p{output} || %p );
 }
 
@@ -484,41 +472,41 @@
 sub _change_params {
 
   sub _change_array {
-    my ($converter, $aref)  = @_;
+    my ($charset, $aref)  = @_;
     foreach (@$aref) {
       my $type = ref $_;
       if ( $type eq 'HASH' ) {
-        _change_hash( $converter, $_ );
+        _change_hash( $charset, $_ );
       } elsif ( $type eq 'ARRAY' ) {
-        _change_array( $converter, $_ );
+        _change_array( $charset, $_ );
       } else {
-        $_ = $converter->convert($_) || die "Can not convert from default_input_charset to default_output_charset" if $_;
+        $_ = Encode::decode($charset, $_);
       }
     }
   }
 
   sub _change_hash {
-    my ($converter, $href)  = @_;
+    my ($charset, $href)  = @_;
     foreach ( values %$href ) {
       my $type = ref $_;
       if ( $type eq 'HASH' ) {
-        _change_hash( $converter, $_ );
+        _change_hash( $charset, $_ );
       } elsif ( $type eq 'ARRAY' ) {
-        _change_array( $converter, $_ );
+        _change_array( $charset, $_ );
       } else {
-        $_ = $converter->convert($_) || die "Can not convert from default_input_charset to default_output_charset" if $_;
+        $_ = Encode::decode($charset, $_);
       }
     }
   }
-  my $converter = shift;
+  my $charset = shift;
   for ( my $i = 1 ; $i <= $#_ ; $i += 2 ) {
     my $type = ref $_[$i];
     if ( $type eq 'HASH' ) {
-      _change_hash( $converter, $_[$i] );
+      _change_hash( $charset, $_[$i] );
     } elsif ( $type eq 'ARRAY' ) {
-      _change_array( $converter, $_[$i] );
+      _change_array( $charset, $_[$i] );
     } else {
-      $_[$i] = $converter->convert($_[$i]) || die "Can not convert from default_input_charset to default_output_charset" if $_[$i];
+      $_[$i] = Encode::decode($charset, $_[$i]);
     }
   }
 }
diff -Nur a/lib/Apache/PageKit/View.pm b/lib/Apache/PageKit/View.pm
--- a/lib/Apache/PageKit/View.pm	2004-03-12 10:15:16.000000000 +0100
+++ b/lib/Apache/PageKit/View.pm	2004-03-12 10:15:28.000000000 +0100
@@ -181,11 +181,13 @@
     my $fif;
     if(@{$view->{fillinform_objects}}){
       $view->{pkit_pk}->{browser_cache} = 'no';
+      my $state = Encode::_utf8_off($output);
       $fif = HTML::FillInForm->new();
       $output = $fif->fill(scalarref => \$output,
                            fobject   => $view->{fillinform_objects},
 			   ignore_fields => $view->{ignore_fillinform_fields}
 			  );
+       Encode::_utf8_on($output) if $state;
     }
   }
   if($view->{can_edit} eq 'yes'){
@@ -456,24 +458,12 @@
     # currently only XML::LibXSLT is supported
     $template_ref = $view->{content}->generate_template($page_id, $component_id, $pkit_view, $view->{input_param_object}, $component_params);
   } else {
+    my $default_input_charset = $view->{default_input_charset};
     open TEMPLATE, "<$template_file" or die "can not read $template_file";
-    binmode TEMPLATE;
+    binmode TEMPLATE, ":encoding($default_input_charset)";
     local($/) = undef;
     my $template = <TEMPLATE>;
     close TEMPLATE;
-
-    my $default_input_charset = $view->{default_input_charset};
-    unless($default_input_charset eq 'UTF-8'){
-      my $converter;
-      eval {
-	$converter = Text::Iconv->new($default_input_charset, 'UTF-8');
-      };
-      if ($@) {
-	(my $config_dir = $view->{content_dir}) =~ s!/Content$!/Config!;
-	die "charset ($default_input_charset) is not supported by Text::Iconv please check file ${config_dir}/Config.xml";
-      }
-      $template = $converter->convert($template) || die "Can not convert page from $default_input_charset to utf-8" if $template;
-    }
     
     # expand PKIT_MACRO tags
     $template =~ s!<\s*PKIT_MACRO$key_value_pattern\s*/?>!$component_params->{uc($+)} || ''!egi;
@@ -520,18 +510,6 @@
   # remove PKIT_COMMENT parts.
   my $pkit_comment_re = $re_helper{ $view->{relaxed_parser} eq 'yes' ? 'relaxed_parser' : 'std_parser' }->{pkit_comment_re};
   $$template_ref =~ s/$pkit_comment_re//sgi;
-  
-  my $default_output_charset = $view->{default_output_charset};
-  my $converter;
-  unless ('UTF-8' eq $default_output_charset) {
-    eval {
-      $converter = Text::Iconv->new( 'UTF-8', $default_output_charset);
-    };
-    if ($@) {
-      (my $config_dir = $view->{content_dir}) =~ s!/Content$!/Config!;
-      die "The charset ($default_output_charset) is not supported by Text::Iconv please check file ${config_dir}/Config.xml";
-    }
-  }
 
 #  my $template_file = $view->_find_template($pkit_view, $page_id);
   my $lang_tmpl = $content->process_template($page_id, $template_ref);
@@ -544,10 +522,6 @@
   # go through content files (which have had content filled in)
   while (my ($lang, $filtered_html) = each %$lang_tmpl){
 
-    if ( $converter ) {
-      $$filtered_html = $converter->convert($$filtered_html) || die "Can not convert page from UTF-8 to $default_output_charset" if $$filtered_html;
-    }
-
     my $exclude_params_set = $view->_preparse_model_tags($filtered_html);
     $view->_html_clean($filtered_html);
 
@@ -605,7 +579,6 @@
 }
 
 sub _preparse_model_tags {
-  use bytes;
   my ( $view, $html_code_ref ) = @_;
 
   my $exclude_params_set = {};
diff -Nur a/lib/Apache/PageKit.pm b/lib/Apache/PageKit.pm
--- a/lib/Apache/PageKit.pm	2004-03-12 10:15:16.000000000 +0100
+++ b/lib/Apache/PageKit.pm	2004-03-12 10:15:28.000000000 +0100
@@ -19,7 +19,7 @@
 use HTML::Parser ();
 use HTML::Entities ();
 use HTML::Template ();
-use Text::Iconv ();
+use Encode ();
 use XML::LibXML ();
 
 $| = 1;
@@ -754,7 +754,7 @@
     my $fo_file = "$view_cache_dir/$$.fo";
     my $pdf_file = "$view_cache_dir/$$.pdf";
     open FO_TEMPLATE, ">$fo_file" or die "can't open file: $fo_file ($!)";
-    binmode FO_TEMPLATE;
+    binmode FO_TEMPLATE, ":encoding($default_output_charset)";
     print FO_TEMPLATE $$output_ref;
     close FO_TEMPLATE;
 
@@ -798,12 +798,10 @@
     my $data;
     while (@charsets){
       $retcharset = (shift @charsets)->[0];
-      last if ($retcharset eq $default_output_charset);
       eval {
-        my $converter = Text::Iconv->new($default_output_charset, $retcharset);
-        $converted_data = $converter->convert($$output_ref);
+        $converted_data = Encode::encode( $retcharset, $$output_ref, Encode::FB_CROAK );
       };
-      last if ($converted_data);
+      last unless ( $@ );
       $retcharset = undef;
     }
 
@@ -811,8 +809,13 @@
     ## we deliver in our default_output_charset.
 
     # correct the header
-    $apr->content_type("text/html; charset=$retcharset") if ($retcharset);
-    $apr->content_type("text/html")                      unless ($retcharset);
+    if ($retcharset) {
+      $apr->content_type("text/html; charset=$retcharset");
+    }
+    else {
+      $apr->content_type("text/html");
+      $converted_data = Encode::encode( $default_output_charset, $$output_ref, Encode::FB_DEFAULT );
+    }
   }
 
   # only pages with propper $retcharset are tranfered gzipped.
__THIS_IS_THE_END__

#

use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

###########################################
# install_checker, contrib by Boris Zentner

##use vars qw( %Requirements %Recommended %Example );

use vars qw( %h );

%h = (
  '5.006' => {

    # version is the minimum version required to run

    Requirements => {
                      'Apache::Test'          => { version => 1.05 },
                      'Apache::SessionX'      => {},
                      'Compress::Zlib'        => {},
                      'Data::FormValidator'   => {},
                      'Digest::MD5'           => {},
                      'HTML::FillInForm'      => { version => 0.12 },
                      'HTML::Template'        => { version => 2.2 },
                      'HTML::Template::XPath' => { version => 0.10 },
                      'HTML::Clean'           => {},
                      'Text::Iconv'           => {},
                      'XML::LibXML' => { version => 1.31, comment => '(you need libxml2 >= 2.4.10 and libxslt >= 1.0.9)' },
    },

    Recommended => {
                    'Mail::Mailer'    => { comment => '(only needed if you use Apache::ErrorReport)' },
                    'Apache::DBI'     => { comment => '(*strongly* recommended if you use DBI)' },
                    'MIME::Types'     => { comment => '(needed if you want to serve static files from View/Default directory)' },
                    'XML::LibXSLT'    => { version => 1.31, comment => '(needed if you want to use XSLT tranformations)' },
                    'Storable'        => { version => 1.013, comment => '(needed for heavy loaded servers)' },
                    'Locale::gettext' => { version => 1.01,  comment => '(needed if you want to localize pkit messages)' },
    },

    Example => {
                 'DBD::CSV'       => {},
                 'HTTP::Headers'  => {},
                 'SQL::Statement' => {},
                 'Text::CSV_XS'   => {},
                 'Apache::Reload' => {},
    }
  },
  '5.008' => {

    # version is the minimum version required to run

    Requirements => {
                      'Apache::Test'          => { version => 1.05 },
                      'Apache::SessionX'      => {},
                      'Compress::Zlib'        => {},
                      'Data::FormValidator'   => {},
                      'Digest::MD5'           => {},
                      'HTML::FillInForm'      => { version => 0.12 },
                      'HTML::Template'        => { version => 2.2 },
                      'HTML::Template::XPath' => { version => 0.10 },
                      'HTML::Clean'           => {},
                      'Encode'                => {},
                      'XML::LibXML' => { version => 1.31, comment => '(you need libxml2 >= 2.4.10 and libxslt >= 1.0.9)' },
    },

    Recommended => {
                    'Mail::Mailer' => { comment => '(only needed if you use Apache::ErrorReport)' },
                    'Apache::DBI'  => { comment => '(*strongly* recommended if you use DBI)' },
                    'MIME::Types' => { comment => '(needed if you want to serve static files from View/Default directory)' },
                    'XML::LibXSLT' => { version => 1.31, comment => '(needed if you want to use XSLT tranformations)' },
                    'Storable'        => { version => 1.013, comment => '(needed for heavy loaded servers)' },
                    'Locale::gettext' => { version => 1.01,  comment => '(needed if you want to localize pkit messages)' },
    },

    Example => {
                 'DBD::CSV'       => {},
                 'HTTP::Headers'  => {},
                 'SQL::Statement' => {},
                 'Text::CSV_XS'   => {},
                 'Apache::Reload' => {},
    }
  },
);

#insert _name and _installed_version into the hash(s)
sub init {
  my $mods_ref = shift;
  for ( keys %$mods_ref ) {
    $mods_ref->{$_}{_name} = $_;
    eval {
      no strict "refs";
      ( my $fname = $_ ) =~ s!::!/!g;
      require "${fname}.pm";

      my $version = "$_" . "::VERSION";
      if ( defined $$version ) {
        $mods_ref->{$_}{_installed_version} = $$version;
      }
      else {

        # module installed, but no $VERSION var
        $mods_ref->{$_}{_installed_version} = 0;
      }
    };
    if ($@) {
      unless ( $@ =~ m!^Can't locate \S+ in \@INC! ) {

        # assume module can't be loaded outside of mod_perl (e.g. Apache::DBI)
        $mods_ref->{$_}{_installed_version} = 0;
      }
    }
  }
}

sub show_versions {
  my @hrefs = @_;
  my @res   = ();
  my $len   = 0;
  for my $href (@hrefs) {
    for ( keys %$href ) {
      if ( defined( $href->{$_}{_installed_version} ) ) {
        $len = length if length > $len;
        push @res, $href->{$_};
      }
    }
  }

  if (@res) {
    for ( sort { $a->{_name} cmp $b->{_name} } @res ) {
      printf "  %-${len}s %6s %s\n", $_->{_name}, $_->{_installed_version}, $_->{comment} || '';
    }
  }
}

sub check_mods {
  my $title_install = shift;
  my $title_update  = shift;
  my @install       = ();
  my @update        = ();
  my $ilen          = 0;
  my $ulen          = 0;

  for my $href (@_) {
    for ( keys %$href ) {
      if ( !defined $href->{$_}{_installed_version} ) {
        $ilen = length if ( length > $ilen );
        push @install, $href->{$_};
      }
      elsif (    defined $href->{$_}{_installed_version}
              && defined $href->{$_}{version}
              && $href->{$_}{_installed_version} < $href->{$_}{version} ) {
        $ulen = length if ( length > $ulen );
        push @update, $href->{$_};
      }
    }
  }

  if (@install) {
    print "$title_install\n";
    for ( sort { $a->{_name} cmp $b->{_name} } @install ) {
      printf "  %-${ilen}s %s\n", $_->{_name}, $_->{comment} || '';
    }
  }

  if (@update) {
    print "$title_update\n";
    for ( sort { $a->{_name} cmp $b->{_name} } @update ) {
      printf "  %-${ulen}s (%s) to at least %s %s\n", $_->{_name}, $_->{_installed_version}, $_->{version},
        $_->{comment} || '';
    }
  }
}

my @versions = sort keys(%h);
my $vers     = $versions[0];
for (@versions) {
  if ( $] >= $_ ) {
    $vers = $_;
  }
  else {
    last;
  }
}

init($_) for ( $h{$vers}{Requirements}, $h{$vers}->{Recommended}, $h{$vers}{Example} );
my $update = 'Please update the following module(s):';
check_mods( "You need to install the following module(s) to run PageKit:\n", $update, $h{$vers}{Requirements} );
check_mods( "\nYou should install the following module(s) to run PageKit:\n",  $update, $h{$vers}{Recommended} );
check_mods( "\nYou need to install the following module(s) to run the PageKit Example Server:\n", $update, $h{$vers}{Example} );
print "\n";

# end install_checker
###################################

use lib qw;t;;
use Apache::Test 1.05;
use Apache::TestMM qw/test clean/;

Apache::TestMM::filter_args();
Apache::TestMM::generate_script('t/TEST');

my $prereq_pm = {
                   'Apache::Test'          => 1.05,
                   'Apache::URI'           => 0,
                   'Apache::Cookie'        => 0,
                   'Apache::Request'       => 0,
                   'Apache::SessionX'      => 0,
                   'Apache::Util'          => 0,
                   'Compress::Zlib'        => 0,
                   'Data::FormValidator'   => 0,
                   'HTML::Clean'           => 0,
                   'HTML::FillInForm'      => 0.12,
                   'HTML::Template'        => 2.2,
                   'HTML::Template::XPath' => 0.10,
                   'Text::Iconv'           => 0,
                   'XML::LibXML'           => 1.53,
                   mod_perl                => 1.2401
  };

if ( $] >= 5.008 ) {
  delete $prereq_pm->{'Text::Iconv'};
  $prereq_pm->{Encode} = 0;
}

WriteMakefile(
  'NAME'         => 'Apache::PageKit',
  'AUTHOR'       => 'T.J. Mather <tjmather\@thoughtstore.com>',
  'VERSION_FROM' => 'lib/Apache/PageKit.pm',                                                          # finds $VERSION
  'clean'        => { FILES => "t/TEST t/httpd t/error_log eg/View/pkit_cache/* eg/conf eg/htdocs eg/logs patch_file.diff patch_blib" },
  'PREREQ_PM'    => $prereq_pm
);

