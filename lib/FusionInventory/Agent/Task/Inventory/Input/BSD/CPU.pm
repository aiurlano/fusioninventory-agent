package FusionInventory::Agent::Task::Inventory::Input::BSD::CPU;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Generic;

sub isEnabled {
    return canRun('dmidecode');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};

    my $speed;
    my $hwModel = getFirstLine(command => 'sysctl -n hw.model');
    if ($hwModel =~ /([\.\d]+)GHz/) {
        $speed = $1 * 1000;
    }

    foreach my $cpu (getCpusFromDmidecode()) {
        $cpu->{SPEED} = $speed;
        $inventory->addEntry(
            section => 'CPUS',
            entry   => $cpu
        );
    }

}

1;
