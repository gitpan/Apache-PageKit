use strict;

$^W = 1;

print "1..3\n";

use Apache::PageKit::Content;
use Digest::MD5;

print "ok 1\n";

my $content = Apache::PageKit::Content->new(content_dir => "eg/Content",
					default_lang => 'en');

my $langs = $content->get_languages('language');

my $lang_string = join(" ",sort @$langs);

my $expected_string = 'de en es fr';

print "got '$lang_string' expected '$expected_string'\nnot "
	unless $lang_string eq $expected_string;
print "ok 2\n";

my $nodeset = $content->get_xpath_nodeset(content_id=>'language',
					xpath=>'title',
					lang=>'de');

my $title_string = $nodeset->string_value;

$expected_string = 'Titel auf Deutsch';

print "got '$title_string' expected '$expected_string'\nnot "
	unless $title_string eq $expected_string;
print "ok 3\n";

__END__
my $param_hashref = $content->get_param_hashref('language');

print "got $param_hashref->{'content:title'}END\nnot " unless $param_hashref->{'content:title'} eq 'Title in English';
print "ok 2\n";
