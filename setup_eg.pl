# required for example web site to run
use DBD::CSV;
use Digest::MD5;
use SQL::Statement;
use Text::CSV_XS;
use Apache::Reload;

# use Apache::test to test PageKit (using eg/ code)
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
