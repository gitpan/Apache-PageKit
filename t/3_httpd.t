use strict;

$^W = 1;

print "1..1\n";

use Apache::test;
use Digest::MD5;

my $response = Apache::test->fetch("http://localhost:8228/langauge");

print "not " unless Digest::MD5->md5_hex($response->content) eq "3d404606d10d1c842d8ac4501b4c0b7f";

print "ok 1\n";
