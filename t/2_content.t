use strict;

$^W = 1;

print "1..2\n";

use Apache::PageKit::Content;
use Digest::MD5;

print "ok 1\n";

my $content = Apache::PageKit::Content->new(content_dir => "eg/Content",
					default_lang => 'de');

$content->parse_all;

my $param_hashref = $content->get_param_hashref('language');

print "got $param_hashref->{'content:title'}END\nnot " unless $param_hashref->{'content:title'} eq 'Titel auf Deutsch';
print "ok 2\n";
