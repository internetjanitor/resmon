package Core::Apache;

use strict;
use warnings;

use base 'Resmon::Module';

use Resmon::ExtComm qw(run_command cache_command);
use Socket;
use Fcntl;
use IO::Select;
use IO::Handle;

=pod

=head1 NAME

Core::Apache - Gather statitistcs from Apache mod_status

=head1 SYNOPSIS

 Core::Apache {
     localhost : noop
 }

 Core::Apache {
     localhost : host => 127.0.0.1, port => 80, url => /server-status?auto
 }

=head1 DESCRIPTION

This module connects to TCP services and tests for a response.

=head1 CONFIGURATION

=over

=item check_name

The check name is used for descriptive purposes only.  It is not used for
anything functional.

=item host

Override the default host. Default value is localhost.

=item port

Override the default port. Default value is 80.

=item url

Override the default url.  Default value is /server-status?auto.

=back

=head1 METRICS

This check returns all metrics from Apache mod_status

=cut

sub handler {
    my $self = shift;
    my $config = $self->{'config'};
    my $host = $config->{'host'} || "localhost";
    my $port = $config->{'port'} || 80;
    my $url = $config->{'url'} || "/server-status?auto";
    my $timeout=10;
    my %metrics;
    my $proto = getprotobyname('tcp');
    my $c = IO::Select->new();
    my $h = IO::Handle->new();


    my %scoreboard = ( '_' => 'Waiting',
                       'S' => 'Starting',
                       'R' => 'Reading',
                       'W' => 'Sending',
                       'K' => 'Keepalive',
                       'D' => 'DNS_Lookup',
                       'C' => 'Closing',
                       'L' => 'Logging',
                       'G' => 'Graceful',
                       'I' => 'Idle',
                       '\.' => 'Open' );

    my $scorekey = join('', keys %scoreboard);

    socket($h, Socket::PF_INET, Socket::SOCK_STREAM, $proto) || return { 'status' => ['socket error', 's'] };
    $h->autoflush(1);

    fcntl($h, Fcntl::F_SETFL, Fcntl::O_NONBLOCK) || (close($h) && return { 'status' => ['fcntl error', 's'] } );

    my $s = Socket::sockaddr_in($port, Socket::inet_aton($host));
    connect($h, $s);
    $c->add($h);
    my ($fd) = $c->can_write($timeout);
    if ($fd == $h) {
        my $error = unpack("s", getsockopt($h, Socket::SOL_SOCKET, Socket::SO_ERROR));
        if ($error != 0) {
            close($h);
            return { 'status' => ['connection failed', 's'] };
        }
        print $h "GET " . $url . " HTTP/1.0\n\n";
        #print $h "Host: " . $host . "\n\n";
        ($fd) = $c->can_read($timeout);
        if ($fd == $h) {
          while (my $l = <$h>) {
            last if ($l =~ m/^\s*$/); # Skip headers
          }
          while (my $l = <$h>) {
            if ($l =~ m/^(.*):\s([0-9\.]+)$/) {
                my $m = $1;
                my $v = $2;
                $m =~ s/\s+/_/g;
                $metrics{$m} = $v;
            } elsif ($l =~ m/^Scoreboard:\s([$scorekey]*)/) {
              my $score = $1;
              foreach my $k (keys %scoreboard) {
                my $count = 0; $count++ while $score =~ /$k/g;
                $metrics{'Slot' . $scoreboard{$k}} = $count;
              }
            }
          }
        }
        close($h);
    }
    close($h);

    return \%metrics;

};

1;
