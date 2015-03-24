#!/usr/bin/perl

# 040409, blb: written

# dircleanbysize.pl - if above ubound, remove files (oldest or largest)
#	usage:
#	perl dircleanbysize.pl  dir_to_clean  upper_bound  reduce_by
#
#	(upper_bound & reduce_by in megabytes)

# get parameters
($Dir, $ubound, $reduceby) = @ARGV;

# quick sanity checks
(defined $Dir)			or die "Path parameter required.\n";
(-d $Dir)			or die "Path parameter $Dir must exist.\n";
(not $Dir =~ /\.\.?$/)		or die "Relative paths not allowed.\n";
(defined $ubound)		or die "Must have directory upper size megabytes.\n";
(defined $reduceby)		or die "Must have reduction megabytes. (0 is OK.)\n";
($reduceby < $ubound)		or die "Reduction larger than or equal to upper limit.\n";

# constants
my $idx_bytes = 7;		# 8th stat array item: size
my $idx_mtime = 9;
my $mbyte = 1024 * 1024;
my $aoaidx_bytes = 1;		# 2nd sub-array item: size
my $aoaidx_mtime = 2;

# inits
my $dh = "";
my @files = ();
my @FArry = ();

# program control (until we add parameter decoding tree)
my $datesort = 1;		# 1 = delete oldest first, 0 = biggest

opendir($dh,$Dir)		or die "Can't open $Dir dir for read.\n";
@files = readdir($dh);		# read 'em all at once
closedir($dh);

for (@files) {				# build array of arrays
        next if $_ eq '.';
        next if $_ eq "..";
	next if -l "$Dir/$_";		# ignore links
	next if -d _;			# ignore directories
	next unless -f _;		# only include regular files (?)
        @fstat = stat _;		# stat just once, uses -f cache!
        push @FArry, [ ($_, @fstat[$idx_bytes], @fstat[$idx_mtime]) ];
}

if ($datesort) {			# sort for ordered deletion
	@FArry = sort {			# by date (oldest to newest)
        	my @a_flds = @$a;
        	my @b_flds = @$b;

        	$a_flds[$aoaidx_mtime] <=> $b_flds[$aoaidx_mtime]
                	||		# break date tie with size
        	$b_flds[$aoaidx_bytes] <=> $a_flds[$aoaidx_bytes]
	}
	@FArry;
}
else {
	@FArry = sort {			# by size (largest to smallest)
        	my @a_flds = @$a;
        	my @b_flds = @$b;

        	$b_flds[$aoaidx_bytes] <=> $a_flds[$aoaidx_bytes]
                	||		# break size tie with date
        	$a_flds[$aoaidx_mtime] <=> $b_flds[$aoaidx_mtime]
	}
	@FArry;
};

sub dofstotal {				# sum size "column" of "global" array
        my $idx = shift;		# nth column in sublists
        my $istart = shift;		# start summing here in master array
        my $fstotal = 0;
        for my $i ( $istart .. $#FArry ) {	# note hard-coded array name!
                $fstotal += @{$FArry[$i]}->[$idx];
        }
        $fstotal
};

if (($ubound * $mbyte) <= &dofstotal($aoaidx_bytes,0)) {	# beyond limit?
	$ubound -= $reduceby;		# create "reduce to" megabytes
	$ubound *= $mbyte;		# convert megabytes to bytes
	my @fnarry;			# what we'll delete list
	for (my $i = 0; $ubound <= &dofstotal($aoaidx_bytes,$i); $i++) {
		push @fnarry, @{$FArry[$i]}->[0];	# save name in list
	};				# chdir below saves repeated string space
	chdir $Dir	or die "Cannot cd to $Dir dir.\n";
	unlink @fnarry;			# delete entire list with one call
};

