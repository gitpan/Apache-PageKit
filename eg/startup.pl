# $Id: startup.pl,v 1.1.1.1 2000/08/25 02:57:38 tjmather Exp $

use strict;

# make sure we are in a sane environment.
$ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl/
  or die "GATEWAY_INTERFACE not Perl!";

# Modules used by your Business Model and MyPageKit
use Apache::DBI ();  # Apache::DBI should come first, before DBI is loaded
use Digest::MD5 ();

# PageKit module
use Apache::PageKit ();

# Module used to implement session management
use Apache::Session::MySQL ();

# MyPageKit modules
use MyPageKit ();
use MyPageKit::ModuleCode ();
use MyPageKit::PageCode ();

# init the connections for each child
Apache::DBI->connect_on_init("DBI:driver:db:host","username","password");
