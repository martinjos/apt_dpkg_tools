#!/usr/bin/perl -w
use strict;

use DpkgStored;

print "Looking up $ARGV[0]...\n";

my $s = DpkgStored->new('/var/lib/dpkg/status');
print $s->get($ARGV[0]);
