package Apache::PageKit::Error;

# $Id: Error.pm,v 1.3 2000/10/31 22:51:23 tjmather Exp $

use integer;
use strict;

use Mail::Mailer;

# trap die and warn

$main::SIG{__WARN__} = \&Apache::PageKit::Error::warn;
$main::SIG{__DIE__} = \&Apache::PageKit::Error::die;

$Apache::PageKit::Error::in_use = 'yes';

sub errorMessage {

  return if $Apache::PageKit::Error::in_use eq 'no';

  my $r = Apache->request;

  my $s = Apache->server;

  return unless $r;

  if($r->dir_config('PKIT_ERROR_HANDLER') eq 'email'){

    my $uri = (split(' ',$r->the_request))[1];
    $uri .= '?' . $r->notes('query_string') if $uri !~ /\?/;

    my $userID = $r->connection->user;

    my $host = $r->header_in('Host');
    my $remote_host = $r->header_in('X-Forwarded-For') || $r->get_remote_host;
    my $referer = $r->header_in('Referer');

    my $current_callback = $r->current_callback;

    my $message = <<END;
$uri
userID: $userID  host: $host  remote_host: $remote_host  referer: $referer
handler: $current_callback

$_[0]

END
    my $i = 0;
    while (my ($package, $filename, $line, $subr) = caller($i)){
      $message .= "stack $i: $package $subr line $line\n";
      $i++;
    }
    my $mailer = new Mail::Mailer;
    $mailer->open({To => $s->server_admin,
		   Subject => "Website $_[1]"
		  });
    print $mailer $message;
    $mailer->close;
  } elsif ($r->dir_config('PKIT_ERROR_HANDLER') eq 'display') {
    my $color = $_[1] eq 'WARN' ? 'blue' : 'red';
    my $message = $_[0];
    $message =~ s/</&lt;/g;
    $message =~ s/>/&gt;/g;
    print qq{<pre><font color="$color">$_[1]: $message};
    my $i = 0;
    while (my ($package, $filename, $line, $subr) = caller($i)){
      print "stack $i: $package $subr line $line\n";
      $i++;
    }
    print qq{</font></pre><br>};
  }
}

sub warn {
  &errorMessage($_[0],"WARN");
}

sub die {
  &errorMessage($_[0],"FATAL");
}

1;

__END__

=head1 NAME

Apache::PageKit::Error - Error Handling under mod_perl

=head1 SYNOPSIS

In your perl code or C<startup.pl> file:

  use Apache::PageKit::Error;

In your Apache configuration file:

  PerlSetVar PKIT_ERROR_HANDLER email

=head1 DESCRIPTION

Redirects warnings and fatal errors to screen or e-mail by using
C<__WARN__> and C<__DIE__> signal handlers.  Includes detailed information
including error message, call stack, uri, host, remote host, remote user,
referrer, and handler.

If C<PKIT_ERROR_HANDLER> is set to I<display>, errors will be
displayed on the screen for easy debugging.  This should be used in a development
environment only.

If C<PKIT_ERROR_HANDLER> is set to I<email>, errors will be e-mailed to the site
adminstrator as specified in the Apache C<ServerAdmin> configuration directive.
This should be used on a production site.

=head1 AUTHOR

T.J. Mather (tjmather@thoughtstore.com)

=head1 COPYRIGHT

Copyright (c) 2000, ThoughtStore, Inc.  All rights Reserved.  PageKit is a trademark
of ThoughtStore, Inc.

=head1 LICENSE

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the Ricoh Source Code Public License for more details.

You can redistribute this module and/or modify it only under the terms of the Ricoh Source Code Public License.

You should have received a copy of the Ricoh Source Code Public License along with this program; if not, obtain one at http://www.pagekit.org/license

=cut
