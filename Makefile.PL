
use inc::Module::Install;
use English qw(-no_match_vars);

name 'FusionInventory-Agent';
include 'Module::AutoInstall';
abstract 'FusionInventory unified Agent for UNIX, Linux, Windows and MacOSX';
license 'gpl';
version_from 'lib/FusionInventory/Agent.pm';
perl_version '5.008';

# mandatory dependencies
requires 'Digest::MD5'        => undef;
requires 'File::Which'        => undef;
requires 'LWP'                => '5.8';
requires 'Net::IP'            => undef;
requires 'UNIVERSAL::require' => undef;
requires 'Text::Template'     => undef;
requires 'XML::TreePP'        => '0.26';

if ($OSNAME eq 'darwin') {
    requires 'Mac::SysProfile' => undef;
}

# optional dependencies
recommends 'Compress::Zlib'   => undef;
recommends 'HTTP::Daemon'     => undef;
recommends 'Net::CUPS'        => 0.60;
recommends 'IO::Socket::SSL'  => undef;
recommends 'LWP::Protocol::https'  => undef;

if ($OSNAME ne 'MSWin32') {
    recommends 'Proc::Daemon'     => undef;
    recommends 'Proc::PID::File'  => undef;
} else {
    requires 'Win32::OLE' => undef;
    requires 'Win32::TieRegistry' => undef;
}

# test dependencies
test_requires  'HTTP::Proxy'                  => undef;
test_requires  'HTTP::Server::Simple'         => undef;
test_requires  'HTTP::Server::Simple::Authen' => undef;
test_requires  'IO::Socket::SSL'              => undef;
test_requires  'IO::Capture::Stderr'          => undef;
test_requires  'IPC::Run'                     => undef;
test_requires  'Test::Exception'              => undef;
test_requires  'Test::MockModule'             => undef;
test_requires  'Test::More'                   => '0.93'; # subtest
test_requires  'YAML'                         => undef;
test_requires  'LWP::Protocol::https'          => undef;

install_script  'fusioninventory-agent';
install_script  'fusioninventory-win32-service' if $OSNAME eq 'MSWin32';
install_script  'fusioninventory-injector';
# memconf is needed by Solaris backend module
install_script  'memconf' if $OSNAME eq 'solaris';

makemaker_args(
    test => {
        TESTS => join ' ', map { glob } qw(t/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t)
    },
);

WriteAll;

# substitute prefix everywhere
$MY::variables{SYSCONFDIR} =~ s/\$\(PREFIX\)/$MY::variables{PREFIX}/;
$MY::variables{DATADIR} =~ s/\$\(PREFIX\)/$MY::variables{PREFIX}/;
$MY::variables{LOCALSTATEDIR} =~ s/\$\(PREFIX\)/$MY::variables{PREFIX}/;

# look for already existing configuration file
my $config_file_message = -f "$MY::variables{SYSCONFDIR}/agent.cfg" ?
    "previous configuration file found, new one will be installed as agent.cfg.new" :
    "no previous configuration file found, new one will be installed as agent.cfg";

print <<EOF;

Installation summary
--------------------
prefix: $MY::variables{PREFIX}
configuration installation directory: $MY::variables{SYSCONFDIR}
constant data installation directory: $MY::variables{DATADIR}
variable data installation directory: $MY::variables{LOCALSTATEDIR}

$config_file_message
EOF

package MY;

use English qw(-no_match_vars);

our %variables;

# force a perl-independant prefix for everything
sub constants {
    my ($self) = @_;

    # for some reason, initialising variables from the global scope doesn't work
    %variables = (
        PREFIX               => '/usr/local',
        INSTALLSCRIPT        => '$(PREFIX)/bin',
        INSTALLSITESCRIPT    => '$(PREFIX)/bin',
        INSTALLVENDORSCRIPT  => '$(PREFIX)/bin',
        INSTALLLIB           => '$(DATADIR)/lib',
        INSTALLSITELIB       => '$(DATADIR)/lib',
        INSTALLVENDORLIB     => '$(DATADIR)/lib',
        INSTALLMAN1DIR       => '$(PREFIX)/share/man/man1',
        INSTALLSITEMAN1DIR   => '$(PREFIX)/share/man/man1',
        INSTALLVENDORMAN1DIR => '$(PREFIX)/share/man/man1',
        INSTALLMAN3DIR       => '$(PREFIX)/share/man/man3',
        INSTALLSITEMAN3DIR   => '$(PREFIX)/share/man/man3',
        INSTALLVENDORMAN3DIR => '$(PREFIX)/share/man/man3',
        SYSCONFDIR           => '$(PREFIX)/etc/fusioninventory',
        DATADIR              => '$(PREFIX)/share/fusioninventory',
        LOCALSTATEDIR        => '$(PREFIX)/var/fusioninventory',
    );

    # allow variables defined on command line to override defaults
    foreach my $name (keys %variables) {
        $variables{$name} = $self->{ARGS}->{$name} if $self->{ARGS}->{$name};
    }

    # get all standard MM variables definitions, and override them if needed
    my @code = split(/\n/, $self->SUPER::constants(@_));
    foreach my $line (@code) {
        # Skip comments
        next if $line =~ /^\s*#/;
        # Skip everything which isn't a var assignment.
        next unless $line =~ /^([A-Z0-9_]+) =/;
        my $name = $1;
        # skip variables we're not interested
        next unless $variables{$name};

        $line = "$name = $variables{$name}";
    }

    # add out own variables
    foreach my $name (qw/SYSCONFDIR DATADIR LOCALSTATEDIR/) {
        push @code, "$name = $variables{$name}";
    }

    return join("\n", @code);
}

sub install {
    my ($self) = @_;
    my $install = $self->SUPER::install(@_);

    # add dependency on data and configuration installation targets, and remove
    # dependency on perlocal installation target
    $install =~ s/install :: pure_install doc_install/install :: pure_install config_install data_install/;

    # suppress all lines related to packlist file installation
    $install =~ s/.*\.packlist \\\n//g;

    # add data and configuration installation targets
    $install .= <<'EOF';

config_install :
	install -d -m 755 $(DESTDIR)$(SYSCONFDIR)
	if [ -f $(DESTDIR)/$(SYSCONFDIR)/agent.cfg ]; then \
	    install -m 644 etc/agent.cfg $(DESTDIR)$(SYSCONFDIR)/agent.cfg.new; \
	else \
	    install -m 644 etc/agent.cfg $(DESTDIR)$(SYSCONFDIR)/agent.cfg; \
	fi

data_install :
	install -d -m 755 $(DESTDIR)$(DATADIR)
	install -m 644 share/pci.ids $(DESTDIR)$(DATADIR)/
	install -d -m 755 $(DESTDIR)$(DATADIR)/html
	install -m 644 share/html/* $(DESTDIR)$(DATADIR)/html
EOF
    return $install;
}

# ensure binaries get modified to use configured directories (on Unix only)
sub installbin {
    my ($self) = @_;
    my $installbin = $self->SUPER::installbin(@_);

    return $installbin if $OSNAME eq 'MSWin32';

    $installbin =~ s|\t\$\(FIXIN\) (.*)\n|\t\$(FIXIN) $1\n\t\$(FINALIZE) $1\n|g;

    $installbin .= <<'EOF';
FINALIZE = $(ABSPERLRUN) -pi \
    -e 's|use lib .*|use lib "$(DATADIR)/lib";|;' \
    -e 's|confdir => .*|confdir => "$(SYSCONFDIR)",|;' \
    -e 's|datadir => .*|datadir => "$(DATADIR)",|;' \
    -e 's|libdir  => .*|libdir  => "$(DATADIR)/lib",|;' \
    -e 's|vardir  => .*|vardir  => "$(LOCALSTATEDIR)",|' \
    --
EOF
    return $installbin;
}

sub manifypods {
    my ($self) = @_;
    my $manifypods = $self->SUPER::manifypods(@_);
    $manifypods =~ s/manifypods : pure_all/manifypods : pure_all fusioninventory-agent.1.html/;
    $manifypods .= <<'EOF';
fusioninventory-agent.1.html: fusioninventory-agent
	pod2html --infile=$< --outfile=$@

EOF
    return $manifypods;
}
