package FusionInventory::Agent::Task::Inventory::OS::MacOS::Mem;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::MacOS;

my %speedMatrice = (
    mhz => 1,
    ghz => 1000,
);
my %sizeMatrice = (
    mb => 1,
    gb => 1000,
    tb => 1000*1000,
);

sub isInventoryEnabled {
    return 
        -r '/usr/sbin/system_profiler';
}

sub doInventory {
    my $params = shift;
    my $inventory = $params->{inventory};
    my $logger = $params->{logger};

    my $memories = getMemories($logger);

    return unless $memories;

    foreach my $memory (@$memories) {
        $inventory->addMemory($memory);
    }
}

sub getMemories {
    my ($logger, $file) = @_;

    my $infos = getInfosFromSystemProfiler($logger, $file);

    return unless $infos->{Memory};

    # the memory slot informations may appears directly under
    # 'Memory' top-level node, or under Memory/Memory Slots
    my $parent_node = $infos->{Memory}->{'Memory Slots'} ?
        $infos->{Memory}->{'Memory Slots'} :
        $infos->{Memory};

    my $memories;
    # memori
    foreach my $key (sort keys %$parent_node) {
        next unless $key =~ /DIMM(\d)/; 
        my $slot = $1;

        my $info = $parent_node->{$key};

        my $memory = {
            NUMSLOTS     => $slot,
            DESCRIPTION  => $info->{'Part Number'},
            CAPTION      => "Status: $info->{'Status'}",
            TYPE         => $info->{'Type'},
            SERIALNUMBER => $info->{'Serial Number'}
        };

        if ($info->{'Size'} && $info->{'Size'} =~ /^(\d+) \s (\S+)$/x) {
            $memory->{CAPACITY} = $1 * $sizeMatrice{lc($2)};
        }

        if ($info->{'Speed'} && $info->{'Speed'} =~ /^(\d+) \s (\S+)$/x) {
            $memory->{SPEED} = $1 * $speedMatrice{lc($2)};
        }

        cleanUnknownValues($memory);

        push @$memories, $memory;
    }

    return $memories;
}

1;
