use strict;

$^W = 1;

print "1..1\n";

use Apache::test;
use Digest::MD5;

my $response = Apache::test::fetch("http://localhost:8228/language");

my $MD5_hex = Digest::MD5->md5_hex($response);
my $expected_hex = 'afe3294709dc876fde3f3985eacc4f74';
print "got MD5_hex $MD5_hex\n"unless $MD5_hex eq $expected_hex;
print "not " unless $MD5_hex eq $expected_hex;

print "ok 1\n";
