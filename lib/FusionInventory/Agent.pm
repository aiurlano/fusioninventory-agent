package FusionInventory::Agent;

use strict;
use warnings;

use POE;

use Cwd;
use English qw(-no_match_vars);
use Pod::Usage;
use Sys::Hostname;

use FusionInventory::Agent::Config;
use FusionInventory::Agent::Scheduler;
use FusionInventory::Agent::Storage;
use FusionInventory::Agent::Target::Local;
use FusionInventory::Agent::Target::Stdout;
use FusionInventory::Agent::Target::Server;
use FusionInventory::Agent::Transmitter;
use FusionInventory::Agent::Receiver;
use FusionInventory::Agent::XML::Query::Prolog;
use FusionInventory::Logger;

our $VERSION = '2.2.0';
our $VERSION_STRING =
    "FusionInventory unified agent for UNIX, Linux and MacOSX ($VERSION)";
our $AGENT_STRING =
    "FusionInventory-Agent_v$VERSION";

$ENV{LC_ALL} = 'C'; # Turn off localised output for commands
$ENV{LANG} = 'C'; # Turn off localised output for commands

sub new {
    my ($class, $params) = @_;

    my $self = {
        status => 'unknown',
        token  => _computeNewToken()
    };
    bless $self, $class;

    my $config = $self->{config} = FusionInventory::Agent::Config->new($params);

    if ($config->{help}) {
        pod2usage(-verbose => 0);
        exit 0;
    }
    if ($config->{version}) {
        print $VERSION_STRING . "\n";
        exit 0;
    }

    my $logger = $self->{logger} = FusionInventory::Logger->new({
        config => $config
    });

    if (!$config->{server} && !$config->{local} && !$config->{stdout}) {
        $logger->fault(
            "No target defined. Use at least one of --server, --local or " .
            "--stdout option"
        );
        exit 1;
    }

    if ($REAL_USER_ID != 0) {
        $logger->info("You should run this program as super-user.");
    }

    if (! -d $config->{'share-dir'}) {
        $logger->fault("Non-existing data directory $config->{'share-dir'}.");
        exit 1;
    }

    $logger->debug("Data directory: $config->{'share-dir'}");

    #my $hostname = Encode::from_to(hostname(), "cp1251", "UTF-8");
    my $hostname;
  
    if ($OSNAME eq 'MSWin32') {
        eval {
            require Encode;
            require Win32::API;
            Encode->import();

            my $GetComputerName = Win32::API->new(
                "kernel32", "GetComputerNameExW", ["I", "P", "P"], "N"
            );
            my $lpBuffer = "\x00" x 1024;
            my $N = 1024; #pack ("c4", 160,0,0,0);

            my $return = $GetComputerName->Call(3, $lpBuffer,$N);

            # GetComputerNameExW returns the string in UTF16, we have to change
            # it # to UTF8
            $hostname = encode(
                "UTF-8", substr(decode("UCS-2le", $lpBuffer),0,ord $N)
            );
        };
    } else {
        $hostname = hostname();
    }

    my $storage = FusionInventory::Agent::Storage->new({
        logger    => $logger,
        directory => $config->{basevardir}
    });
    my $data = $storage->restore();

    if (
        !defined($data->{previousHostname}) ||
        $data->{previousHostname} ne $hostname
    ) {
        my ($year, $month , $day, $hour, $min, $sec) =
            (localtime(time()))[5,4,3,2,1,0];
        $data->{deviceid} = sprintf "%s-%02d-%02d-%02d-%02d-%02d-%02d",
            $hostname, ($year + 1900), ($month + 1), $day, $hour, $min, $sec;
        $data->{previousHostname} = $hostname;
        $storage->save({ data => $data });
    }
    $self->{deviceid} = $data->{deviceid};

    $self->{scheduler} = FusionInventory::Agent::Scheduler->new({
        logger     => $logger,
        lazy       => $config->{lazy},
        wait       => $config->{wait},
        background => $config->{daemon} || $config->{service}
    });

    if ($config->{stdout}) {
        $self->{scheduler}->addTarget(
            FusionInventory::Agent::Target::Stdout->new({
                logger     => $logger,
                config     => $config,
                maxOffset  => $config->{delaytime},
                basevardir => $config->{basevardir},
                deviceid =>   $self->{deviceid},
            })
        );
    }

    if ($config->{local}) {
        $self->{scheduler}->addTarget(
            FusionInventory::Agent::Target::Local->new({
                logger     => $logger,
                config     => $config,
                maxOffset  => $config->{delaytime},
                basevardir => $config->{basevardir},
                path       => $config->{local},
                deviceid =>   $self->{deviceid},
            })
        );
    }

    if ($config->{server}) {
        foreach my $url (split(/,/, $config->{server})) {
            $url =~ s/^\s+//;
            $url =~ s/\s+$//;
            $self->{scheduler}->addTarget(
                FusionInventory::Agent::Target::Server->new({
                    logger     => $logger,
                    config     => $config,
                    maxOffset  => $config->{delaytime},
                    basevardir => $config->{basevardir},
                    url        => $url,
                    deviceid =>   $self->{deviceid},
                })
            );
        }
    }

    if ($config->{scanhomedirs}) {
        $logger->debug("User directory scanning enabled");
    }

    if ($config->{daemon} && !$config->{'no-fork'}) {

        $logger->debug("Daemon mode enabled");

        my $cwd = getcwd();
        Proc::Daemon->require();
        if ($EVAL_ERROR) {
            $logger->fault("Can't load Proc::Daemon. Is the module installed?");
            exit 1;
        }
        Proc::Daemon::Init();
        $logger->debug("Daemon started");
        if ($self->_isAgentAlreadyRunning()) {
            $logger->fault("An agent is already runnnig, exiting...");
            exit 1;
        }
        # If we are in dev mode, we want to stay in the source directory to
        # be able to access the 'lib' directory
        chdir $cwd if $config->{devlib};

    }

    if (($config->{daemon} || $config->{service}) && ! $config->{'no-www'}) {
        FusionInventory::Agent::Receiver->require();
        if ($EVAL_ERROR) {
            $logger->debug("Failed to load Receiver module: $EVAL_ERROR");
        } else {
            $self->{receiver} = FusionInventory::Agent::Receiver->new({
                logger    => $logger,
                scheduler => $self->{scheduler},
                agent     => $self,
                devlib    => $config->{devlib},
                share_dir => $config->{'share-dir'},
                ip        => $config->{'www-ip'},
                port      => $config->{'www-port'},
                trust_localhost => $config->{'www-trust-localhost'},
            });
        }
    }

    $logger->debug("FusionInventory Agent initialised");

    return $self;
}

sub _isAgentAlreadyRunning {
    my ($self) = @_;

    # TODO add a workaround if Proc::PID::File is not installed
    eval {
        require Proc::PID::File;
        return Proc::PID::File->running();
    };
    $self->{logger}->debug(
        'Proc::PID::File unavalaible, unable to check for running agent'
    ) if $EVAL_ERROR;

    return 0;
}

sub run {
    my ($self) = @_;

    my $config = $self->{config};
    my $logger = $self->{logger};
    my $scheduler = $self->{scheduler};
    my $receiver = $self->{receiver};



    foreach my $target (@{$scheduler->{targets}}) {
        # Create the POE session
        $target->createSession(); 
    }

    POE::Kernel->run();
    exit;

}

sub getToken {
    my ($self) = @_;
    return $self->{token};
}

sub resetToken {
    my ($self) = @_;
    $self->{token} = _computeNewToken();
}

sub _computeNewToken {
    my @chars = ('A'..'Z');
    return join('', map { $chars[rand @chars] } 1..8);
}

sub getStatus {
    my ($self) = @_;
    return $self->{status};
}

1;

__END__

=head1 NAME

FusionInventory::Agent - Fusion Inventory agent

=head1 DESCRIPTION

This is the agent object.

=head1 METHODS

=head2 new()

The constructor. No arguments allowed.

=head2 run()

Run the agent.

=head2 getToken()

Get the current authentication token.

=head2 resetToken()

Reset the current authentication token to a new random value.

=head2 getStatus()

Get the current agent status.
