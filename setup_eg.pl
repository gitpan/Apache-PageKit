# required for example web site to run
use DBD::CSV;
use Digest::MD5;
use SQL::Statement;
use Text::CSV_XS;
use Apache::Reload;
use Cwd;
use File::Path;

# use Apache::test to test PageKit (using eg/ code)
use Apache::test;
my %params = Apache::test->get_test_params();
my $pwd    = cwd;
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

%dirs = (
          unix => {
                    csvdb_dir         => '/tmp/csvdb',
                    sessions_dir      => '/tmp/pkit_sessions',
                    sessions_lock_dir => '/tmp/pkit_sessions_lock'
          },
          MSWin32 => {
                     csvdb_dir         => 'c:/tmp/csvdb',
                     sessions_dir      => 'c:/tmp/pkit_sessions',
                     sessions_lock_dir => 'c:/tmp/pkit_sessions_lock'
          },
);

$os = ( exists $dirs{$^O} ) ? $^O : 'unix';

Apache::test->write_httpd_conf( %params, include => $more_directives );
*MY::test = sub { Apache::test->MM_test(%params) };

for my $dir ( values %{ $dirs{$os} } ) {
  mkpath($dir);
  chmod 0777, $dir;
}

$csvdb_dir = $dirs{$os}->{csvdb_dir};

my $dbh = DBI->connect("DBI:CSV:f_dir=$csvdb_dir");
if ( -e "$csvdb_dir/pkit_user" ) {
  $dbh->do("DROP TABLE pkit_user");
}
$dbh->do("CREATE TABLE pkit_user (user_id CHAR(8), login CHAR(255), email CHAR(255), passwd CHAR(255))");
$dbh->disconnect;
