package FusionInventory::LoggerBackend::File;

use strict;
use warnings;

use English qw(-no_match_vars);

sub new {
    my ($class, $params) = @_;

    my $self = {
        logfile         => $params->{config}->{'logfile'},
        logfile_maxsize => $params->{config}->{'logfile-maxsize'}
    };

    bless $self, $class;

    $self->open();

    return $self;
}

sub open {
    my ($self) = @_;

    open $self->{handle}, '>>', $self->{logfile}
        or warn "Can't open $self->{logfile}: $ERRNO";
}


sub watchSize {
    my ($self) = @_;

    return unless $self->{logfile_maxsize};

    my $size = (stat($self->{handle}))[7];

    if ($size > $self->{logfile_maxsize} * 1024 * 1024) {
        close $self->{handle};
        unlink($self->{logfile}) or die "$!!";
        $self->open();
        print {$self->{handle}}
            "[".localtime()."]" .
            " max size reached, log file truncated\n";
    }

}

sub addMsg {
    my ($self, $args) = @_;

    my $level = $args->{level};
    my $message = $args->{message};

    return if $message =~ /^$/;

    $self->watchSize();

    print {$self->{handle}}
        "[". localtime() ."]" .
        "[$level]" .
        " $message\n";
}

sub DESTROY {
    my ($self) = @_;

    close $self->{handle};
}

1;
