package FusionInventory::Agent::Task::Inventory::Input::Generic::Dmidecode::Battery;

use strict;
use warnings;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Generic;

sub isEnabled {
    return 1;
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $battery = _getBattery(logger => $logger);

    return unless $battery;

    $inventory->addEntry(
        section => 'BATTERIES',
        entry   => $battery
    );
}

sub _getBattery {
    my $infos = getDmidecodeInfos(@_);

    return unless $infos->{22};

    my $info    = $infos->{22}->[0];

    my $battery = {
        NAME         => $info->{'Name'},
        MANUFACTURER => $info->{'Manufacturer'},
        SERIAL       => $info->{'Serial Number'},
        CHEMISTRY    => $info->{'Chemistry'},
    };

    if ($info->{'Manufacture Date'}) {
        $battery->{DATE} = _parseDate($info->{'Manufacture Date'});
    }

    if ($info->{'Design Capacity'} &&
        $info->{'Design Capacity'} =~ /(\d+) \s m(W|A)h$/x) {
        $battery->{CAPACITY} = $1;
    }

    if ($info->{'Design Voltage'} &&
        $info->{'Design Voltage'} =~ /(\d+) \s mV$/x) {
        $battery->{VOLTAGE} = $1;
    }

    return $battery;
}

sub _parseDate {
    my ($string) = @_;

    my ($day, $month, $year);
    if ($string =~ /(\d{1,2}) [\/-] (\d{1,2}) [\/-] (\d{2})/x) {
        $day   = $1;
        $month = $2;
        $year  = ($3 > 90 ? "19" : "20" ) . $3;
        return "$day/$month/$year";
    } elsif ($string =~ /(\d{4}) [\/-] (\d{1,2}) [\/-] (\d{1,2})/x) {
        $year  = $1;
        $day   = $2;
        $month = $3;
        return "$day/$month/$year";
    }

    return;
}

1;
