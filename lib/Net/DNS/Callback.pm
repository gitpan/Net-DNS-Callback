package Net::DNS::Callback;

use strict;
use warnings;
use vars qw($VERSION);
use Net::DNS::Resolver;
use IO::Select;
use Time::HiRes;

$VERSION = '1.03';

sub new {
	my $class = shift;
	my $self = ($#_ == 0) ? { %{ (shift) } } : { @_ };
	$self->{QueueSize} = 20 unless $self->{QueueSize};
	$self->{Timeout} = 4 unless $self->{Timeout};
	$self->{Resolver} = new Net::DNS::Resolver();
	$self->{Selector} = new IO::Select();
	$self->{Retries} = 3 unless $self->{Retries};
	return bless $self, $class;
}

sub add {
	my ($self, $callback, @query) = @_;

	unless (ref($callback) eq 'CODE') {
		die "add() requires a CODE reference as first arg";
	}
	unless (@query) {
		die "add() requires a DNS query as trailing args";
	}

	# print "Queue size " . scalar(keys %{ $self->{Queue} });
	while (scalar(keys %{ $self->{Queue} }) > $self->{QueueSize}) {
		# I'm fairly sure this can't busy wait since it must
		# either time out an entry or receive an entry.
		$self->recv();
	}

	my $data = [ $callback, \@query, 0, undef, undef ];
	$self->send($data);
}

sub cleanup {
	my ($self, $data) = @_;

	my $socket = $data->[4];
	if ($socket) {
		$self->{Selector}->remove($socket);
		delete $self->{Queue}->{$socket->fileno};
		$socket->close();
	}
}

sub send {
	my ($self, $data) = @_;

	my $socket = $self->{Resolver}->bgsend(@{$data->[1]});

	unless ($socket) {
		die "No socket returned from bgsend()";
	}
	unless ($socket->fileno) {
		die "Socket returned from bgsend() has no fileno";
	}

	$data->[3] = time();
	$data->[4] = $socket;

	$self->{Queue}->{$socket->fileno} = $data;
	$self->{Selector}->add($socket);
}

sub recv {
	my $self = shift;
	my $time = shift;

	unless (defined $time) {
		$time = time();
		# Find first timer.
		for (values %{ $self->{Queue} }) {
			$time = $_->[3] if $_->[3] < $time;
		}
		# Add timeout, and compute delay until then.
		$time = $time + $self->{Timeout} - time();
		# It could have been a while ago.
		$time = 0 if $time < 0;
	}

	my @sockets = $self->{Selector}->can_read($time - time());
	for my $socket (@sockets) {
		# If we recursed from the user callback into add(), then
		# we might have read from and closed this socket.
		# XXX A neater solution would be to collect all the
		# callbacks and perform them after this loop has exited.
		next unless $socket->fileno;
		$self->{Selector}->remove($socket);
		my $data = delete $self->{Queue}->{$socket->fileno};
		unless ($data) {
			die "No data for socket " . $socket->fileno;
		}
		my $response = $self->{Resolver}->bgread($socket);
		$socket->close();
		eval {
			$data->[0]->($response);
		};
		if ($@) {
			die "Callback died within " . __PACKAGE__ . ": $@";
		}
	}

	$time = time();
	for (values %{ $self->{Queue} }) {
		if ($_->[3] + $self->{Timeout} < $time) {
			# It timed out.
			$self->cleanup($_);
			if ($self->{Retries} < ++$_->[2]) {
				$_->[0]->(undef);
			}
			else {
				$self->send($_);
			}
		}
	}
}

sub await {
	my $self = shift;
	$self->recv while keys %{ $self->{Queue} };
}

*done = \&await;

=head1 NAME

Net::DNS::Callback - Asynchronous DNS helper for high volume applications

=head1 SYNOPSIS

	use Net::DNS::Callback;

	my $c = new Net::DNS::Callback(QueueSize => 20, Retries => 3);

	for (...) {
		$c->add(\&callback, @query);
	}
	$c->await();

	sub callback {
		my $response = shift;
		...
	}

=head1 DESCRIPTION

Net::DNS::Callback is a fire-and-forget asynchronous DNS helper.
That is, the user application adds DNS questions to the helper, and
the callback will be called at some point in the future without
further intervention from the user application. The application need
not handle selects, timeouts, waiting for a response or any other
such issues.

This module is similar in principle to POE::Component::Client::DNS,
but does not require POE.

=head1 CONSTRUCTOR

The class method new(...) constructs a new helper object. All arguments
are optional. The following parameters are recognised as arguments
to new():

=over 4 

=item QueueSize

The size of the query queue. If this is exceeded, further calls to
add() will block until some responses are received or time out.

=item Retries

The number of times to retry a query before giving up.

=item Timeout

The timeout for an individual query.

=back

=head1 METHODS

=over 4

=item $c->add($callback, @query)

Adds a new query for asynchronous handling. The @query arguments are
those to Net::DNS::Resolver->bgsend(), q.v. This call will block
if the queue is full. When some pending responses are received or
timeout events occur, the call will unblock.

The user callback will be called at some point in the future, with
a Net::DNS::Packet object representing the response. If the query
timed out after the specified number of retries, the callback will
be called with undef.

=item $c->await()

Flushes the queue, that is, waits for and handles all remaining
responses.

=back

=head1 BUGS

The test suite does not test query timeouts.

=head1 SEE ALSO

L<Net::DNS>,
L<POE::Component::Client::DNS>

=head1 COPYRIGHT

Copyright (c) 2005-2006 Shevek. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
