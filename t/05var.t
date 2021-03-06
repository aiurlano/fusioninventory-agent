#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use English qw(-no_match_vars);

plan(skip_all => 'Author test, set $ENV{TEST_AUTHOR} to a true value to run')
    if !$ENV{TEST_AUTHOR};

eval { require Test::Vars; };
plan(skip_all => 'Test::Vars required') if $EVAL_ERROR;

Test::Vars->import();
if ($OSNAME eq 'MSWin32') {
    push @INC, 't/fake/unix';
} else {
    push @INC, 't/fake/windows';
}

all_vars_ok(
    ignore_vars => {
        '%params'   => 1,
        '$class'    => 1,
        '$request'  => 1, # FusionInventory::Agent::HTTP::Server
        '$clientIp' => 1, # FusionInventory::Agent::HTTP::Server
        '$num'      => 1  # Task::Inventory::Input::Solaris::Networks
    }
);
