package Circos::Debug;

=pod

=head1 NAME

Circos::Debug - debugging routines for Circos

=head1 SYNOPSIS

This module is not meant to be used directly.

=head1 DESCRIPTION

Circos is an application for the generation of publication-quality,
circularly composited renditions of genomic data and related
annotations.

Circos is particularly suited for visualizing alignments, conservation
and intra and inter-chromosomal relationships. However, Circos can be
used to plot any kind of 2D data in a circular layout - its use is not
limited to genomics. Circos' use of lines to relate position pairs
(ribbons add a thickness parameter to each end) is effective to
display relationships between objects or positions on one or more
scales.

All documentation is in the form of tutorials at L<http://www.circos.ca/tutorials>.

=cut

# -------------------------------------------------------------------

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(start_timer stop_timer format_timer report_timer printerror printdebug printdebug_group printdumper printwarning printinfo printout debug_or_group);

use Carp qw( carp confess croak );
use Data::Dumper;
use FindBin;
use Memoize;
use Time::HiRes qw(gettimeofday tv_interval);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
#use Circos::Configuration qw(%CONF);

# -------------------------------------------------------------------
sub list_as_string {
    my $empty_text = $Circos::Configuration::CONF{debug_empty_text} || "_emptylist_";
    return $empty_text if ! @_;
    my $sep        = $Circos::Configuration::CONF{debug_word_separator} || " ";
    my $undef_text = $Circos::Configuration::CONF{debug_undef_text} || "_undef_";
    return join($sep, map { defined $_ ? $_ : $undef_text } @_);
}

# -------------------------------------------------------------------
sub debuginfo {
    my $info = <<ENDINFO;
If you are having trouble diagnosing this error, use Circos' debugging facility to follow the program as it is running.

To turn on summary debugging messages, use -debug. 

  circos ... -debug

  or

  circos ... -debug_group summary 

To extend debugging to other components, use -debug_group. 

  circos ... -debug_group summary 
  circos ... -debug_group summary,timer
  circos ... -debug_group summary,timer,io
  circos ... -debug_group summary,timer,io,color

To show *all* debugging, use

  circos ... -debug_group _all

To generate a dump of data parsed from the configuration file, use -cdump.

For more information about debugging, including a list of all the debug component names, see

  http://circos.ca/tutorials/lessons/configuration/debugging/

ENDINFO
}

# -------------------------------------------------------------------
sub errorheader {
    my %args   = @_;
    my $width  = $args{width} || 50;
    my $margin_width = $args{margin} || 2;
    my $delim  = $args{delim} || "*";
    my $text   = $args{text}  || "error";
    my $hdr    = $delim x $width;
    my $margin = " " x $margin_width;
    substr($hdr,(length($hdr) - length($text) - $margin_width*2)/2,length($text)+2*$margin_width) = $margin.$text.$margin;

    return $hdr;
}

# -------------------------------------------------------------------
sub printerror {
    printinfo();
    printinfo(errorheader());
    printinfo();
    printinfo(@_);
    printinfo(errorheader(text=>"debugging"));
    printinfo();
    printinfo(debuginfo());
}

# -------------------------------------------------------------------
sub printdebug {
    if($Circos::Configuration::CONF{debug}) {
	printinfo('debug', @_);
    }
}

# -------------------------------------------------------------------
{
    my $t = [gettimeofday];
    sub printdebug_group {
	my ($group,@msg) = @_;
	if(debug_or_group($group)) {
	    printinfo('debuggroup',$group,sprintf("%.2fs",tv_interval($t)),@msg);
	}
    }
}

sub format_timer {
    my $t = shift;
    return sprintf("%.3f s",tv_interval($t));
}

{
    my $timers    = {};
    my @lasttimer = ();
    sub start_timer {
	my $timer = shift;
	return if $timers->{$timer}{start};
	$timers->{$timer}{start}   = [gettimeofday];
	$timers->{$timer}{elapsed} ||= 0;
	push @lasttimer, $timer;
    }
    sub stop_timer {
	my $timer = shift;
	if(! defined $timer) {
	    $timer = pop @lasttimer;
	}
	return unless defined $timers->{$timer}{start};
	@lasttimer = grep($_ ne $timer, @lasttimer);
	$timers->{$timer}{elapsed} += tv_interval( $timers->{$timer}{start} );
	delete $timers->{$timer}{start};
    }
    sub report_timer {
	my $timer = shift;
	my @timers;
	if(! defined $timer) {
	    @timers = sort keys %$timers;
	} else {
	    @timers = ($timer);
	}
	for my $t (@timers) {
	    stop_timer($t);
	    if(defined $timers->{$t}{elapsed}) {
	      printdebug_group("timer","report",$t,sprintf("%.3f s",$timers->{$t}{elapsed}));
	    } else {
	      # no such timer
	    }
	  }
      }
  }

# -------------------------------------------------------------------
sub debug_or_group {
    my $group = shift;
    return if 
	! defined $Circos::Configuration::CONF{debug_group} &&
	! defined $Circos::Configuration::CONF{debug};
    confess "No group defined." if ! defined $group;
    #printdumper(\%Circos::Configuration::CONF);
    #printinfo($Circos::Configuration::CONF{debug_group});
    my $match = 0; # $Circos::Configuration::CONF{debug};
    return $match if ! defined $Circos::Configuration::CONF{debug_group};
    $match ||= $Circos::Configuration::CONF{debug_group} =~ /$group/i;
    if($group =~ /(.+)s$/) {
	my $group_root = $1;
	$match ||= $Circos::Configuration::CONF{debug_group} =~ /$group_root/i;
    }
    $match ||= $Circos::Configuration::CONF{debug_group} =~ /_all/i;
    #printinfo("grouplist",$group,$Circos::Configuration::CONF{debug_group},$match);
    return $match;
}

# -------------------------------------------------------------------
sub printdumper {
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Indent   = 1;
    printinfo( Dumper(@_) );
}

# -------------------------------------------------------------------
sub printwarning {
    if($Circos::Configuration::CONF{warnings}) {
	printinfo( 'warning', @_ );
    }
}

# -------------------------------------------------------------------
sub printinfo {
    if(! @_) {
	printout();
    } else {
	printout( list_as_string(@_) );
    }
}

# -------------------------------------------------------------------
sub printout {
    print "@_\n" unless $Circos::Configuration::CONF{silent};
}

1;
