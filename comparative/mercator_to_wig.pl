#!/usr/bin/perl -w
use strict;

=head1 NAME

=head1 USAGE

=head1 AUTHOR

=cut
# take blocks from mercator and 
# their aligned files and convert into WIG file

use Bio::SeqIO;
use Bio::AlignIO;
use Getopt::Long;
use List::Util qw(max);
use POSIX;

my ($db,$dir,$out);
my $debug = 0;
my $window = 1;

my $type = 'FASALN';
my $name = 'MERCATOR';
my $desc = 'MERCATOR MAVID Percent Identity';
my ($afile,$aformat,$seqformat);
my $refidx = 1; # reference sequence is the db in the GGSEARCH queries

GetOptions('v|verbose!' => \$debug,
	   'f|format:s' => \$aformat,
	   'a|align:s'  => \$afile,
	   'db:s'       => \$db,
	   'd|dir:s'    => \$dir,
	   'o|out:s'    => \$out,
	   'w|window:i' => \$window,
	   'desc:s'     => \$desc,
	   'n|name:s'   => \$name,	   
	   );

if( ! defined $afile ) {
    ($afile,$aformat,$seqformat) = qw(mavid.mfa fasta fasta);
}
}
unless( defined $dir ) {
    die "Need an alignment directory with -d/--dir\n";
}
unless( defined $db ) {
    die "Need a genome database file (FASTA) with -db\n";
}
unless( defined $out ) {
    $out = "$dir.$db.wig"
}
my (%genome,%seen,%lengths);
my $in = Bio::SeqIO->new(-format => $seqformat,
			 -file   => $db);
while( my $seq = $in->next_seq ) {
    my $id        = $seq->display_id;
    $lengths{$id} = $seq->length;
    $genome{$id}->[int($seq->length / $window)] = 0;    
}
opendir(DIR, $dir) || die "cannot open $dir: $!";
open(my $map => "$dir/map" ) || die "cannot open $dir/map\n";
my %dat;
while(<$map>) {
    my @row = split;
}

for my $subdir ( readdir(DIR) ) {
    next unless ( $subdir =~ /^(\d+)$/ );
    warn("block $subdir\n") if $debug;
    my $alnfile = File::Spec->catfile($dir,$subdir,$afile);
    unless( -f $alnfile ) {
	warn("Skipping $subdir, no $afile\n");
	next;
    } else {
	my $alnio = Bio::AlignIO->new(-format => $aformat,
				      -file   => $alnfile);
	if( my $aln = $alnio->next_aln ) {
	    my @ids;
	    my @seqs = map { push @ids, [$_->id,$_->description];
			     $_->seq } $aln->each_seq;
	    my ($hid,$hstart,$hend);
	    if ($ids[$refidx]->[1] =~ /^(\S+)_(\d+)-(\d+)$/) {
		($hid,$hstart,$hend) = ($1,$2,$3);
	    }
	    warn("id is $hid\n");
	    $seen{$hid}++;		    
	    my ($window_start) = int($hstart / $window);
	    my $offset = ($hstart % $window);
	    
		my $c = length($seqs[$refidx]);
		# remove the gaps from the ref since we want ref coords 
		while( ($c = rindex($seqs[$refidx],'-',$c)) > 0) {
		    substr($seqs[$refidx],$c,1,'');
		    substr($seqs[1-$refidx],$c,1,'');
		}
		die "assert seqs are same length" unless(length($seqs[0]) == length($seqs[1]));
		if( $offset > 10 ) {
		    my @preblock = map { substr($_,0,$offset) } @seqs;
		    warn("preblock is \n",join("\n",@preblock),"\n") 
			if $debug;
		    my $pid = &percent_id(@preblock);
		    if ( exists $genome{$hid}->[$window_start] ) {
			$pid = max($genome{$hid}->[$window_start], $pid);
		    }
		    $genome{$hid}->[$window_start++] = $pid;
		}
		my $len = length $seqs[0]; # assume alned seqs are all the same 
		    for( my $i = $offset; $i < $len; $i+= $window ) {
			my $window_cut = $window;
			
			if( $i+$window >= $len ) {
			    $window_cut = $len - $i;
			}			
			my @slice = map { substr($_,$i,$window_cut) } @seqs;
			unless(length $slice[0]) {
			    die("empty slice for $i..$i+$window_cut ",length($seqs[0]),"\n");
			}
			
			warn("i is $i slice is \n",join("\n",@slice),"\n") 
			    if $debug;
			my $pid = &percent_id(@slice);
			if ( exists $genome{$hid}->[$window_start] ) {
			    $pid = max($genome{$hid}->[$window_start], $pid);
			}
			$genome{$hid}->[$window_start++] = $pid
		    }	    
	    }
	} else {
	    warn("unknown type '$type'\n");
	}
    }
    last if $debug;
}

open(my $fh => ">$out") || die "$out; $!";
printf $fh "track type=wiggle_0 name=\"%s\" description=\"%s\"\n",
    $name, $desc;

for my $chrom ( sort { 
	$lengths{$b} <=> $lengths{$a} } 
		keys %genome ) {
    next if( $debug && ! $seen{$chrom});
    printf $fh "fixedStep chrom=%s start=%d step=%d\n",
    $chrom, 1, $window;
    
    for my $w ( @{$genome{$chrom}} ) {
	printf $fh "%d\n",$w || 0;
    }
}

# assumes seqs are aligned and same length!!
sub percent_id {
    my (@seqs) = @_;
    my ($identical,$gaps,$total) = (0,0,0);
    my $length = length($seqs[0]);
    for( my $i = 0; $i < $length; $i++ ) {
	my %seen;
	for my $s ( @seqs ) {
	    $seen{substr($s,$i,1)}++;
	}
	if( keys %seen == 1 ) {
	    $identical++;
	} elsif( $seen{'-'} ) {
	    $gaps++;
	} elsif( $seen{'n'} || $seen{'N'} ) {
	    next;
	}
	$total++;
    }
    unless( $total ) {
	warn("no data in seqs\n");
	return 0;
    } else {
	return POSIX::floor(100 * ($identical / $total));
    }
}
