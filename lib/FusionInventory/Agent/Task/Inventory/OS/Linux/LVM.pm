package FusionInventory::Agent::Task::Inventory::OS::Linux::LVM;

use strict;
use warnings;

use English qw(-no_match_vars);

use FusionInventory::Agent::Tools;


sub isInventoryEnabled {
    can_run("lvs");
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{inventory};

    my $lvs = _parseLvs(
        command => 'lvs -a --noheading --nosuffix --units M -o lv_name,vg_name,lv_attr,lv_size,lv_uuid,seg_count',
        logger  => $logger
    );
    $inventory->addLogicalVolume($_) foreach (@$lvs);

    my $pvs = _parsePvs(
        command => 'pvs --noheading --nosuffix --units M -o +pv_uuid',
        logger  => $logger
    );
    $inventory->addPhysicalVolume($_) foreach (@$pvs);

    my $vgs = _parseVgs(
        command => 'vgs --noheading --nosuffix --units M -o +vg_uuid,vg_extent_size',
        logger  => $logger
    );
    $inventory->addVolumeGroup($_) foreach (@$vgs);
}

sub _parseLvs {
    my $handle = getFileHandle(@_);
    return unless $handle;

    my $entries = [];
    foreach (<$handle>) {
        my @line = split(/\s+/, $_);

        push @$entries, {
            LVNAME => $line[1],
            VGNAME => $line[2],
            ATTR => $line[3],
            SIZE => int($line[4]||0),
            UUID => $line[5],

        };

    }

    return $entries;
}

sub _parsePvs {
    my $handle = getFileHandle(@_);
    return unless $handle;

    my $entries = [];
    foreach (<$handle>) {
        my @line = split(/\s+/, $_);

        push @$entries, {
            DEVICE => $line[1],
            PVNAME => $line[2],
            FORMAT => $line[3],
            ATTR => $line[4],
            SIZE => int($line[5]||0),
            FREE => int($line[6]||0),
            UUID => $line[7],
        }

    }

    return $entries;
}

sub _parseVgs {
    my $handle = getFileHandle(@_);
    return unless $handle;

    my $entries = [];
    foreach (<$handle>) {
        my @line = split(/\s+/, $_);

        push @$entries, {
            VGNAME => $line[1],
            PV_COUNT => $line[2],
            LV_COUNT => $line[3],
            ATTR => $line[5],
            SIZE => $line[6],
            FREE => $line[7],
            UUID => $line[8]
        }

    }

    return $entries;
}

1;