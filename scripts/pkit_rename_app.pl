#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Find  ();
use XML::LibXML ();
use Cwd         ();

# $Id: pkit_rename_app.pl,v 1.1 2004/03/03 13:28:30 borisz Exp $

our $VERSION = 0.01;

my %h;
my $new_name = pop || die <<"ENDE";
Usage:
  $0 MyNewApplicationName
  $0 pkit_rootdir MyNewApplicationName
  
  for more try
    perldoc $0
ENDE

my $eg_root = Cwd::abs_path( pop || '.' );
die <<"ENDE" if !-f "$eg_root/Config/Config.xml" or !-e "$eg_root/Model";
$eg_root is not the root of your application.
  $eg_root/Config/Config.xml or
  $eg_root/Model not found
ENDE

# read the config file
my $parser = XML::LibXML->new;
my $doc    = $parser->parse_file("$eg_root/Config/Config.xml");
my $root   = $doc->documentElement;
my $global = ( $root->findnodes('//GLOBAL')->get_nodelist )[0];
for my $attr ( $global->attributes ) {
  if ( $attr->name =~ /^(?:model_base_class|model_dispatch_prefix)$/ ) {
    $h{ $attr->name } = $attr->value;
  }
}

# check that we have model_base_class and model_dispatch_prefix
die "model_dispatch_prefix or model_base_class is not found in Config/Config.xml"
  unless defined $h{model_dispatch_prefix}
  and defined $h{model_base_class};

# find the directory to rename
my ($prefix_a) = $h{model_dispatch_prefix} =~ /^(.*)::/;
my ($prefix_b) = $h{model_base_class}      =~ /^(.*)::/;

die <<"ENDE" if $prefix_a ne $prefix_b;
$prefix_a ne $prefix_b I give up.
Sure, this may work but NOT with this
script!
ENDE

( my $path = $prefix_a ) =~ s!::!/!g;
-e "$eg_root/Model/$path" || die "Can not find dir $eg_root/Model/$path";

$^I   = '';
@ARGV = "$eg_root/Config/Config.xml";
File::Find::find(
  {
    wanted => sub { /\.pm$/ and -f and push @ARGV, $File::Find::name }
  },
  "$eg_root/Model"
);

while ( defined( $_ = <> ) ) {
  s/\b$prefix_a(?=::)/$new_name/g;
  print;
}
rename "$eg_root/Model/$path", "$eg_root/Model/$new_name";

=pod

=head1 Start a new Application with C<Apache::PageKit>

=head1 Overview

This script renames a Apache::PageKit Application and all the modules. Bellow $pkit_root/Model.

=head1 Requirements

You need a working Apache::PageKit application. Not running, you need only the files. 

=head1 Usage

  pkit_rename_app.pl MyNewAplicationName
  pkit_rename_app.pl pkit_root MyNewAplicationName
   
C<MyNewAplicationName> is the new name for your application.

C<pkit_root> is the name of root of your application. That is the Directory where F<Config>, F<Model>, F<View> and F<Content> is.

=head1 Description

The script renames the application B<INPLACE> so do it on a backup.
It reads the F<Config/Config.xml> to figure out what your old name is.
Then all is the file F<Config/Config.xml> and all your F<*.pm> files are scanned and and replaced with your new App's name. As a last step your directory F<Model/oldname> is moved to F<Model/newname> thats it.

This might become handy if you start a new application and you can reuse a good part of an older one. It is also helpfull if you work on more sites and you have some virtualhosts running F<Apache::Pagekit> applications.

=head1 Example

Now a little example that clones the example site to anotherone.

  cp -r eg a_new_site
  pkit_rename_app.pl a_new_site MyNewSite

=head1 AUTHOR

  Boris Zentner bzm@2bz.de

