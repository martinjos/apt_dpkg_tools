package DpkgStored;

use File::Path;
use DBI;
use Tie::DBI;
use DBD::SQLite;
use File::Copy qw(copy);

my $loc = "$ENV{HOME}/.perl-dpkg-stored";
my $done_init = 0;

sub _init {
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
    $s->_init;
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
	$need_refresh = 1;
	my $dbh = DBI->connect($dbconn,'','');
	$dbh->do('create table hash (k text primary key, v text);');
	$dbh->disconnect;
    } else {
	if (-e $s->{ofn}) {
	    system("diff '$s->{ofn}' '$s->{ffn}' > '$s->{dfn}'");
	}
	my @stat_text = stat($filename);
	my @stat_db = stat($s->{fn});
	if ($stat_text[9] >= $stat_db[9]) {
	    print "Updating table\n";
	    $need_refresh = 1;
	}
    }
    die "Cannot create $s->{fn}" if (! -e $s->{fn});
    if (!-f $s->{fn}) {
	die "$s->{fn} is not an ordinary file";
    }
    tie %{$s->{db}}, 'Tie::DBI', {db => $dbconn, table => 'hash', key => 'k', CLOBBER => 3};
    if ($need_refresh) {
	print "Reloading database from $filename\n";
	open(my $fh, '<', $filename) or die "Can't open $filename";
	my $pkg;
	#%{$s->{db}} = (); # clear all
	my $block;
	local $/ = "\n\n"; # get blocks instead of lines
	while (defined($block = <$fh>)) {
	    if ($block =~ /^Package\s*:\s*(.*)$/m) {
		$pkg = $1;
		#warn "Trying to add $pkg...";
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
	close($fh);
	copy($s->{ffn}, $s->{ofn}); # save backup for next time
    }
    return $s;
}

sub get {
    my ($s, $pkg) = @_;
    return $s->{db}{$pkg}{v};
}

1;
