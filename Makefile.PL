use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Apache::PageKit',
    'VERSION_FROM'	=> 'PageKit.pm', # finds $VERSION
    'PM'		=> {
				'PageKit.pm' => '$(INST_LIBDIR)/PageKit.pm',
				'PageKit/Error.pm' => '$(INST_LIBDIR)/PageKit/Error.pm',
				'PageKit/FormValidator.pm' => '$(INST_LIBDIR)/PageKit/FormValidator.pm',
				'PageKit/Info.pm' => '$(INST_LIBDIR)/PageKit/Info.pm',
				'PageKit/Session.pm' => '$(INST_LIBDIR)/PageKit/Session.pm',
				'PageKit/View.pm' => '$(INST_LIBDIR)/PageKit/View.pm'
			},
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
