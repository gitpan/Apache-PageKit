use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# use Apache::test to test PageKit (using pagekit.org code)
use Apache::test;
my %params = Apache::test->get_test_params();
my $pwd = `pwd`;
chomp($pwd);
$more_directives = <<END;
# PageKit Setup
PerlSetVar PKIT_ROOT $pwd/eg
PerlSetVar PKIT_SERVER staging
SetHandler perl-script
PerlHandler +Apache::PageKit
<Perl>
	Apache::PageKit->startup("$pwd/eg","staging");
</Perl>
PerlInitHandler +Apache::Reload

# Error Handling
PerlModule Apache::ErrorReport
PerlSetVar ErrorReportHandler display
END

Apache::test->write_httpd_conf(%params, include => $more_directives);
*MY::test = sub { Apache::test->MM_test(%params) };

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
				DBD::CSV => 0,
				Digest::MD5 => 0,
				HTML::Clean => 0,
				HTML::FillInForm => 0,
				HTML::Template => 2.2,
				HTTP::Headers => 0,
				Mail::Mailer => 0,
				SQL::Statement => 0,
				Text::CSV_XS => 0,
				XML::Parser => 0,
				XML::XPath => 0,
				mod_perl => 1.2401},
);

mkdir '/tmp/csvdb', 0777;
my $dbh = DBI->connect("DBI:CSV:f_dir=/tmp/csvdb");
if (-e "/tmp/csvdb/pkit_user"){
  $dbh->do("DROP TABLE pkit_user");
}
$dbh->do("CREATE TABLE pkit_user (user_id CHAR(8), login CHAR(255), email CHAR(255), passwd CHAR(255))");
$dbh->disconnect;

mkdir '/tmp/pkit_sessions', 0777;
mkdir '/tmp/pkit_sessions_lock', 0777;
chmod 0777, '/tmp/pkit_sessions', '/tmp/pkit_sessions_lock', '/tmp/pkit_user';
