use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Apache::PageKit',
    'AUTHOR'		=> 'T.J. Mather <tjmather\@thoughtstore.com>',
    'VERSION_FROM'	=> 'lib/Apache/PageKit.pm', # finds $VERSION
    'PREREQ_PM'		=> {Apache::URI => 0,
				Apache::Cookie => 0,
				Apache::Request => 0,
				Apache::Session => 1.5,
				Apache::Util => 0,
				HTML::FillInForm => 0,
				HTML::Template => 0,
				Mail::Mailer => 0,
				XML::Parser => 0,
				URI::Escape => 0},
);
