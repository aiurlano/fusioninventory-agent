package FusionInventory::Logger;

use strict;
use warnings;

# TODO use Log::Log4perl instead.
use English qw(-no_match_vars);
use UNIVERSAL::require;

sub new {
    my ($class, $params) = @_;

    my $self = {
        config   => $params->{config},
        backends => []
    };
    bless $self, $class;

    foreach my $backend (
        $params->{backends} ? @{$params->{backends}} : 'Stderr'
    ) {
        my $package = "FusionInventory::LoggerBackend::$backend";
        $package->require();
        if ($EVAL_ERROR) {
            print STDERR
                "Failed to load Logger backend $backend: ($EVAL_ERROR)\n";
            next;
        }

        $self->debug("Logger backend $backend initialised");
        push
            @{$self->{backends}},
            $package->new({config => $self->{config}});
    }

    $self->debug($FusionInventory::Agent::STRING_VERSION);

    return $self;
}

sub log {
    my ($self, $args) = @_;

    # levels: info, debug, error, fault
    my $level = $args->{level} || 'info';
    my $message = $args->{message};

    return unless $message;
    return if $level eq 'debug' && !$self->{config}->{debug};

    foreach my $backend (@{$self->{backends}}) {
        $backend->addMsg ({
            level => $level,
            message => $message
        });
    }
}

sub debug {
    my ($self, $msg) = @_;

    $self->log({ level => 'debug', message => $msg});
}

sub info {
    my ($self, $msg) = @_;

    $self->log({ level => 'info', message => $msg});
}

sub error {
    my ($self, $msg) = @_;

    $self->log({ level => 'error', message => $msg});
}

sub fault {
    my ($self, $msg) = @_;

    $self->log({ level => 'fault', message => $msg});
}

1;
__END__

=head1 NAME

FusionInventory::Logger - Fusion Inventory logger

=head1 DESCRIPTION

This is the logger object.

=head1 METHODS

=head2 new($params)

The following arguments are allowed:

=over

=item config (mandatory)

=back

=head2 log($args)

Add a log message, with a specific level. The following arguments are allowed:

=over

=item level (mandatory)

Can be one of:

=over

=item debug

=item info

=item error

=item fault

=back

=item message (mandatory)

=back

=head2 debug($msg)

Add a log message with debug level.

=head2 info($msg)

Add a log message with info level.

=head2 error($msg)

Add a log message with error level.

=head2 fault($msg)

Add a log message with fault level.
