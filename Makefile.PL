use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

###########################################
# install_checker, contrib by Boris Zentner

use vars qw( %Requirements %Recommended %Example );

# version is the minimum version required to run

%Requirements = (
  'Apache::Session'  => { version => 1.50 },
  'Compress::Zlib'   => {},
  'Data::FormValidator' => {},
  'Digest::MD5'      => {},
  'HTML::FillInForm' => { version => 0.12 },
  'HTML::Template'   => { version => 2.2 },
  'HTML::Clean'      => {},
  'Mail::Mailer'     => {},
  'Text::Iconv'      => {},
  'XML::Parser'      => {},
  'XML::XPath'       => { version => 1.08 },
);

%Recommended = (
  'Apache::DBI' => { comment => '(*strongly* recommended if you use DBI)' },
  'MIME::Types' =>
  { comment => '(needed if you want to serve static files from View/Default directory)' },
  'XML::LibXML'  => { version => 0.92 },
  'XML::LibXSLT' => { version => 1.04, comment => '(needed if you want to use XSLT tranformations)' },
  'Storable'     => { version => 1.013, comment => '(needed for heavy loaded servers)' },
);

%Example = (
  'DBD::CSV'       => {},
  'HTTP::Headers'  => {},
  'SQL::Statement' => {},
  'Text::CSV_XS'   => {},
  'Apache::Reload' => {},
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
      if ( defined $$version ){
        $mods_ref->{$_}{_installed_version} = $$version;
      } else {
        # module installed, but no $VERSION var
        $mods_ref->{$_}{_installed_version} = 0;
      }
    };
    if($@){
      unless($@ =~ m!^Can't locate \S+ in \@INC!){
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
    for (keys %$href) {
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
  my $ilen = 0;
  my $ulen = 0;

  for my $href (@_) {
    for ( keys %$href ) {
      if ( !defined $href->{$_}{_installed_version} ) {
        $ilen = length if ( length > $ilen );
        push @install, $href->{$_};
      }
      elsif ( defined $href->{$_}{_installed_version} && defined $href->{$_}{version}
        && $href->{$_}{_installed_version} < $href->{$_}{version} )
      {
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
      printf "  %-${ulen}s (%s) to at least %s %s\n", $_->{_name}, $_->{_installed_version},
        $_->{version}, $_->{comment} || '';
    }
  }
}

init($_) for ( \%Requirements, \%Recommended, \%Example );
my $update = 'Please update the following module(s):';
check_mods( "You need to install the following module(s) to run PageKit:", $update,
    \%Requirements );
check_mods( "You should install the following module(s) to run PageKit:", $update,
    \%Recommended );
check_mods( "You need to install the following module(s) to run the PageKit Example Server:",
    $update, \%Example );

# end install_checker
###################################

use Apache::test;

# for make start_httpd and kill_httpd
my $section = Apache::test->MM_test(%params);

#HACK to remove start_httpd from make test
$section =~ s!test :: pure_all start_httpd run_tests   kill_httpd!test :: run_tests!;
 
*MY::test = sub { $section };

WriteMakefile(
    'NAME'		=> 'Apache::PageKit',
    'AUTHOR'		=> 'T.J. Mather <tjmather\@thoughtstore.com>',
    'VERSION_FROM'	=> 'lib/Apache/PageKit.pm', # finds $VERSION
    'clean'		=> {FILES => "t/httpd t/error_log eg/Content/cache/*.dat eg/View/pkit_cache/*"},
    'PREREQ_PM'		=> {Apache::URI => 0,
				Apache::Cookie => 0,
				Apache::Request => 0,
				Apache::Session => 1.5,
				Apache::Util => 0,
			        Compress::Zlib => 0,
				Data::FormValidator => 0,
				HTML::Clean => 0,
				HTML::FillInForm => 0.12,
				HTML::Template => 2.2,
				Mail::Mailer => 0,
			        Text::Iconv => 0,
				XML::Parser => 0,
				XML::XPath => 1.08,
				mod_perl => 1.2401},
);

