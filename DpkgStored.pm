package DpkgStored;

use File::Path;
use DBI;
use Tie::DBI;
use DBD::SQLite;

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
    $s->{filename} = $filename;
    $s->{fn} = "$loc/" . ($filename =~ tr:/:_:r) . ".sqlite";
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
	#$s->{db} = {}; # clear all?
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
    }
    return $s;
}

sub get {
    my ($s, $pkg) = @_;
    return $s->{db}{$pkg}{v};
}

1;
