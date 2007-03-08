package Net::DNS::Callback;

use strict;
use warnings;
use vars qw($VERSION);
use Net::DNS::Resolver;
use IO::Select;
use Time::HiRes;

$VERSION = '1.00';

sub new {
	my $class = shift;
	my $self = ($#_ == 0) ? { %{ (shift) } } : { @_ };
	$self->{QueueSize} = 20 unless $self->{QueueSize};
	$self->{Timeout} = 4 unless $self->{Timeout};
	$self->{Resolver} = new Net::DNS::Resolver();
	$self->{Selector} = new IO::Select();
	return bless $self, $class;
}

sub add {
	my ($self, $callback, @query) = @_;

	# print "Queue size " . scalar(keys %{ $self->{Queue} });
	while (scalar(keys %{ $self->{Queue} }) > $self->{QueueSize}) {
		$self->recv();
	}

	my $data = [ $callback, \@query, 0, undef, undef ];
	$self->send($data);
}

sub send {
	my ($self, $data) = @_;

	my $socket = $data->[4];
	if ($socket) {
		$self->{Selector}->remove($socket);
		delete $self->{Queue}->{$socket->fileno};
		$socket->close();
	}

	$socket = $self->{Resolver}->bgsend(@{$data->[1]});

	$data->[2]++;
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
		$time += $self->{Timeout};
	}

	my @sockets = $self->{Selector}->can_read($time - time());
	for my $socket (@sockets) {
		$self->{Selector}->remove($socket);
		my $data = delete $self->{Queue}->{$socket->fileno};
		my $response = $self->{Resolver}->bgread($socket);
		$data->[0]->($response);
		$socket->close();
	}

	$time = time();
	for (values %{ $self->{Queue} }) {
		if ($_->[3] + $self->{Timeout} < $time) {
			# It timed out.
			$self->send($_);
		}
	}
}

sub done {
	my $self = shift;
	$self->recv while keys %{ $self->{Queue} };
}

=head1 NAME

Net::DNS::Callback - Asynchronous DNS Helper

=head1 SYNOPSIS

	use Net::DNS::Callback;

	my $c = new Net::DNS::Callback(QueueSize => 20);

	for (...) {
		$c->add(\&callback, @query);
	}
	$c->done();

	sub callback {
		my $response = shift;
		...
	}

=head1 CONSTRUCTOR

The class method new(...) constructs a new helper object. All arguments
are optional. The following parameters are recognised as arguments
to new():

=over 4 

=item QueueSize

The size of the query queue. If this is exceeded, further calls to
add() will block until some responses are received or time out.

=item Timeout

The timeout for an individual query.

=back

=head1 METHODS

=over 4

=item $c->add($callback, @query)

Adds a new query for asynchronous handling. The @query arguments are
those to Net::DNS::Resolver->bgsend(), q.v. This call will block
until the queue is less than QueueSize.

=item $c->done()

Flushes the queue, that is, waits for and handles all remaining
responses.

=back

=head1 BUGS

UDP retries are not yet implemented.

=head1 SEE ALSO

L<Net::DNS>

=head1 COPYRIGHT

Copyright (c) 2005-2006 Shevek. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
