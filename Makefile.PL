use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

use Apache::test;

# for make start_httpd and kill_httpd
my $section = Apache::test->MM_test(%params);

# HACK to remove start_httpd from test
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
				HTML::Clean => 0,
				HTML::FillInForm => 0.12,
				HTML::Template => 2.2,
				Mail::Mailer => 0,
			        Text::Iconv => 0,
				XML::Parser => 0,
				XML::XPath => 0,
				mod_perl => 1.2401},
);

