#!perl

use strict;
use warnings FATAL => 'all';

# required for example web site to run
use DBD::CSV;
use Digest::MD5;
use SQL::Statement;
use Text::CSV_XS;
use Cwd;
use File::Path;

my %dirs = (
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

my $os = ( exists $dirs{$^O} ) ? $^O : 'unix';

for my $dir ( values %{ $dirs{$os} } ) {
  mkpath($dir) unless -d $dir;
  chmod 0777, $dir;
}

my $csvdb_dir = $dirs{$os}->{csvdb_dir};

my $dbh = DBI->connect("DBI:CSV:f_dir=$csvdb_dir");
if ( -e "$csvdb_dir/pkit_user" ) {
  $dbh->do("DROP TABLE pkit_user");
}
$dbh->do("CREATE TABLE pkit_user (user_id CHAR(8), login CHAR(255), email CHAR(255), passwd CHAR(255))");
$dbh->disconnect;

use Apache::Test 1.05;
use Apache::TestRunPerl ();
use File::Spec::Functions qw(catfile);

my $root_found;
for ( @ARGV ) {
    $root_found++ if /-documentroot$/;
}
push ( @ARGV, '--documentroot' => catfile Cwd::getcwd() , 'eg' ) unless $root_found;
Apache::TestRunPerl->new->run(@ARGV);

1;
