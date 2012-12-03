package DpkgStored;

use File::Path;
use DBI;
use Tie::DBI;
use DBD::SQLite;
use File::Copy qw(copy);

my $loc = "$ENV{HOME}/.perl-dpkg-stored";
my $done_init = 0;

sub _init_dir {
    return if $done_init;
    
    if (!-e $loc) {
	mkpath($loc);
    }

    if (!-d $loc) {
	die "$loc is not a directory";
    }

    $done_init = 1;
}

sub new {
    my ($perlPkg, $filename) = @_;
    if (!-e $filename) {
	die "$filename does not exist";
    }
    my $s = bless {};
    $s->_init_dir;
    $s->{ffn} = $filename; # "flat" file
    my $label = ($filename =~ tr:/:_:r);
    $s->{fn} = "$loc/$label.sqlite";
    $s->{ofn} = "$loc/$label.old"; # "old" file
    $s->{dfn} = "$loc/$label.diff"; # "diff" file
    my $need_refresh = 0;
    $s->{db} = {};
    my $dbconn = 'dbi:SQLite:dbname='.$s->{fn};
    if (! -e $s->{fn}) {
	print "Creating table\n";
	$need_refresh = 2;
	my $dbh = DBI->connect($dbconn,'','');
	$dbh->do('create table hash (k text primary key, v text);');
	$dbh->disconnect;
    } else {
	if (-e $s->{ofn}) {
	    system("diff '$s->{ofn}' '$s->{ffn}' > '$s->{dfn}'");
	}
	if (-s $s->{dfn}) {
	    print "Updating table\n";
	    $need_refresh = 1;
	}
    }
    die "Cannot create $s->{fn}" if (! -e $s->{fn});
    if (!-f $s->{fn}) {
	die "$s->{fn} is not an ordinary file";
    }
    tie %{$s->{db}}, 'Tie::DBI', {db => $dbconn, table => 'hash', key => 'k', CLOBBER => 3};
    if ($need_refresh == 2) {
	$s->_populate_db
    } elsif ($need_refresh == 1) {
	$s->_repopulate_db
    }
    return $s;
}

sub _add_block {
    my ($s, $block, $verbose) = @_;
    if ($block =~ /^Package\s*:\s*(.*)$/m) {
	$pkg = $1;
	if ($verbose) {
	    print "Adding or updating package $pkg\n";
	}
	if (!defined(eval {
	    $s->{db}{$pkg} = {v => $block};
	})) {
	    #die "Failed to add package $pkg with data:\n$block\nError: $@\n";
	    die "Failed to add package $pkg, Error: $@\n";
	}
    } else {
	warn "No package name in block: $block";
    }
}

sub _remove_package {
    my ($s, $pkg) = @_;
    print "Removing package $pkg (may be re-added later)\n";
    if (!defined(eval {
	delete $s->{db}{$pkg};
    })) {
	warn "Failed to remove package $pkg, Error: $@\n";
    }
}

sub _in_range {
    # N.B.: $start and $end are both inclusive
    my ($start, $end, $ranges) = @_;
    foreach my $range (@$ranges) {
	my ($rs, $rlen) = @$range;
	if ($rs <= $end && $rs + $rlen > $start) {
	    return 1;
	}
    }
    return 0;
}

sub _populate_db {
    my ($s, $ranges) = @_;
    print "Loading database from $s->{ffn}\n" if !defined($ranges);
    open(my $fh, '<', $s->{ffn}) or die "Can't open $s->{ffn}";
    my $pkg;
    #%{$s->{db}} = (); # clear all
    my $block;
    local $/ = "\n\n"; # get blocks instead of lines
    my ($startline, $endline) = (1, 1);
    while (defined($block = <$fh>)) {
	$nls = $block;
	$nls =~ s/[^\n]+//gs; # get only the newlines
	$startline = $endline;
	$endline = $startline + length($nls); # count the newlines
	if (!defined($ranges) || _in_range($startline, $endline - 1, $ranges)) {
	    $s->_add_block($block, defined($ranges));
	}
    }
    close($fh);
    copy($s->{ffn}, $s->{ofn}); # save backup for next time
    print "\n" if !defined($ranges);
}

sub _repopulate_db {
    my ($s) = @_;
    print "Reloading database from $s->{ffn} using diffs in $s->{dfn} (size = " . (-s $s->{dfn}) . ")\n";
    open(my $dfh, '<', $s->{dfn}) or die "Can't open $s->{dfn}";
    my $line;
    my $ranges = [];
    while (defined($line = <$dfh>)) {
	#print $line;
	if ($line =~ /^\<\ Package\s*:\s*(.*)$/m) {
	    #print "Package removed\n";
	    $s->_remove_package($1);
	} elsif ($line =~ / ^ [0-9]+ ([acd]) ([0-9]+) (?: \, ([0-9]+) )? $ /mx) {
	    #print "Something added or changed\n";
	    my ($op, $start, $end) = ($1, $2, $3);
	    my $len = 0;
	    if (defined($end)) {
		$len = $end - $start + 1;
	    } elsif ($op =~ /[ac]/) {
		$len = 1;
	    }
	    push(@{$ranges}, [$start, $len]);
	}
    }
    close($dfh);
    #print scalar(@$ranges) . "\n";
    #foreach my $range (@$ranges) {
	#my ($rs, $rlen) = @$range;
	#print "$rs $rlen\n";
    #}
    $s->_populate_db($ranges);
    print "\n";
}

sub get {
    my ($s, $pkg) = @_;
    return $s->{db}{$pkg}{v};
}

1;
