use strict;

$^W = 1;

print "1..2\n";

use Apache::PageKit::Content;
use Digest::MD5;

print "ok 1\n";

my $content = Apache::PageKit::Content->new(content_dir => "eg/Content",
					default_lang => 'en');

$content->parse_all;

my $param_hashref = $content->get_param_hashref('language');

print "not " unless $param_hashref->{title} eq 'Title in English';
print "ok 2\n";
