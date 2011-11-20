package Circos::Utils;

=pod

=head1 NAME

Circos::Utils - utility routines for Circos

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

All documentation is in the form of tutorials at L<http://www.circos.ca>.

=cut

# -------------------------------------------------------------------

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(
pairwise_or
pairwise_and
round_custom
remap
remap_int
remap_round
str_to_list 
sample_list 
match_string
parse_as_rx
extract_number
compare_strs 
compare_str 
round_up 
seek_parameter 
is_hidden 
defined_but_zero 
defined_and_zero
locate_file
add_thousands_separator
);

use Carp qw( carp confess croak );
use FindBin;
use File::Spec::Functions;
use Math::Round;
use Params::Validate;
use Regexp::Common;

use POSIX qw(floor ceil);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Debug;

sub round_custom {
    my ($x,$round_type) = @_;
    if(! defined $round_type) {
	return int $x;
    } elsif ($round_type eq "round") {
	return round $x;
    } elsif ($round_type eq "floor") {
	return floor $x;
    } elsif ($round_type eq "ceil") {
	return ceil $x;
    }
}
#################################################################
# 
sub remap {
    my ($value,$min,$max,$remap_min,$remap_max) = @_;
    if(! defined $value ||
       ! defined $min ||
       ! defined $max ||
       ! defined $remap_min ||
       ! defined $remap_max) {
	confess "You must pass five parameters to remap(). The syntax is remap(value,min,max,remap_min,remap_max).";
    }
    return $remap_min if $value <= $min;
    return $remap_max if $value >= $max;

    if($min == $max) {
	if($remap_min == $remap_max) {
	    return $remap_min;
	} else {
	    confess "You must pass five parameters to remap(). The syntax is remap(value,min,max,remap_min,remap_max). You have set min=max ($min=$max), but this only makes sense if remap_min=remap_max ($remap_min != $remap_max)";
	}
    }
    my $f = ( $value - $min ) / ( $max - $min );
    my $value_remap = $remap_min + $f * ($remap_max - $remap_min);
    #printinfo($value,$min,$max,$remap_min,$remap_max,$value_remap);
    return $value_remap;
}

sub pairwise_or {
    my ($a,$b,$x,$y) = @_;
    if(! defined $y) {
	confess "You have tried to use the pairwise_or(a,b,x,y) function but one of the values passed to it is not defined.";
    } else {
	return ($a eq $x && $b eq $y) || ($a eq $y && $b eq $x)
    }
}

sub pairwise_and {
    my ($a,$b,$x,$y) = @_;
    if(! defined $y) {
	confess "You have tried to use the pairwise_and(a,b,x,y) function but one of the values passed to it is not defined.";
    } else {
	return $a eq $x && $b eq $y;
    }
}

sub remap_int {
    return int remap(@_);
}

sub remap_round {
    return round remap(@_);
}

sub str_to_list {
    my $str = shift;
    return split(/\s*,\s*/, $str);
}

# -------------------------------------------------------------------
sub sample_list {
# Given a list and regular expression, return the elements in the
# list that match the regular expression.
#
# The results are sorted based on capture buffers from the regular expression.
    my ($rx,$list) = @_;
    my $rev = 0;
    if($rx =~ /rev\((.+)\)/) {
	$rx  = $1;
	$rev = 1;
    }
    confess "Argument in sample_list must be a list" unless ref($list) eq "ARRAY";
    return undef if ! $list;
    my @matches;
    for my $item (@$list) {
	if($item =~ /^$rx$/) {
	    # pull out captured strings
	    my @captures = ();
	    for my $i (1..@+ - 1) {
		my $str = substr($item,$-[$i],$+[$i]-$-[$i]);
		push @captures, $str;
	    }
	    push @matches, {item=>$item,captures=>\@captures};
	}
    }
    my @result = map { $_->{item} } sort { compare_strs($a->{captures},$b->{captures}) } @matches;
    if($rev) {
	return reverse @result;
    } else {
	return @result;
    }
}

sub parse_as_rx {
    my $rx = shift;
    if ($rx =~ /^-?\/(.+)\/$/) {
	return qr/$1/;
    } else {
	return;
    }
}

sub match_string {
    my ($str,$rx) = @_;
    #printinfo(ref($rx));
    return unless defined $rx;
    if(ref($rx)) {
	return $str =~ /$rx/;
    } else {
	return $str eq $rx;
    }
}

# -------------------------------------------------------------------
sub compare_strs {
    my ($list1,$list2) = @_;
    my $result = 0;
    for my $i (0..@$list1-1) {
	return $result if ! defined $list1->[$i] || ! defined $list2->[$i];
	$result ||= compare_str($list1->[$i],$list2->[$i]);
    }
    return $result;
}

# -------------------------------------------------------------------
sub extract_number {
    my $str = shift;
    if($str =~ /0*(\d+)/) {
	return $1;
    } else {
	return "";
    }
}

# -------------------------------------------------------------------
sub compare_str {
    my ($x,$y) = @_;
    if( $x =~ /$RE{num}{real}/ && $y =~ /$RE{num}{real}/ ) {
	$x =~ s/^0*//;
	$y =~ s/^0*//;
	$x ||= 0;
	$y ||= 0;
	return $x <=> $y;
    } else {
	return $x cmp $y;
    }
}

# -------------------------------------------------------------------
sub round_up {
  my $value = shift;
  if($value - int($value) > 0.5) {
    return round($value);
  } else {
    return 1 + int($value);
  }
}

# -------------------------------------------------------------------
sub seek_parameter {
  # Given a parameter name and a list of hash references (or list
  # references to hashes), looks for the parameter and returns the
  # associated value. The parameter will also be extracted from any
  # hash pointed to by the "param" key in the data structure.
  #
  # If the parameter name contains "|" then this is used as a
  # delimiter to define synonyms of the parameter. This is helpful
  # when parameters have changed names but you wish to maintain
  # backward compatibility.
  #
  # value of x returned from $hash
  # seek_parameter("x",$hash);
  # value of x returned from $hash, and if not found, $anotherhash is tried
  # seek_parameter("x",$hash,$anotherhash);
  # value of x or y, whichever is seen first is returned
  # seek_parameter("x|y",$hash,$anotherhash);
  my ( $param_name, @data_structs ) = @_;
  my @target_string = split( /\|/, $param_name );

  for my $str (@target_string) {
    for my $struct (@data_structs) {
      if ( ref($struct) eq "ARRAY" ) {
	for my $substruct (@$struct) {
	    if(exists $substruct->{param} && defined $substruct->{param}{$str}) {
		return $substruct->{param}{$str};
	    }
	    if(exists $substruct->{$str}  && defined $substruct->{$str}) {
		return $substruct->{$str};
	    }
	}
      } elsif ( ref($struct) eq "HASH" ) {
	  if(exists $struct->{param} && defined $struct->{param}{$str}) {
	      return $struct->{param}{$str};
	  }
	  if(exists $struct->{$str} && defined $struct->{$str}) {
	      return $struct->{$str};
	  }
      } else {
	printdumper(\@data_structs);
	croak "cannot extract parameter from this data structure (shown above - report this please)";
      }
    }
  }
  return undef;
}

sub is_hidden {
    my @datapath   = @_;
    my $show_state = seek_parameter("show", @datapath);
    return defined_and_zero($show_state);
}

# -------------------------------------------------------------------
sub locate_file {
    $Circos::Configuration::CONF{debug_validate} && validate( @_, { file => 1, return_undef => 0 } );
    my %params = @_;
    my $file   = $params{file};
    printdebug_group("io","locating file",$file);
    my @dirs;
    if ( -e $file && -r _ ) {
	return $file;
    } elsif ( -e $file && !-r _ ) {
	confess "File [$file] exists, but cannot be read. Do you have permissions to read it?";
    } else {
	# look for the file elsewhere
	@dirs = (
	    "$FindBin::RealBin/../",
	    "$FindBin::RealBin/",       
	    "$FindBin::RealBin/etc",
	    "$FindBin::RealBin/../etc", 
	    "$FindBin::RealBin/../../etc",
	    );
	for my $dir (@dirs) {
	    printdebug_group("io","trying $dir/$file");
	    if ( -e catfile($dir,$file) && -r catfile($dir,$file) ) {
		printdebug_group("io","$file found in $dir/$file");
		return catfile($dir,$file);
	    }
	}
    }
    if ( $params{return_undef} ) {
	return undef;
    } else {
	printinfo("Tried to find file [$file] in these directories, but failed.");
    for my $dir (@dirs) {
      printinfo($dir);
    }
    confess "Could not locate file [$file].";
  }
}

# -------------------------------------------------------------------
sub add_thousands_separator {
  my $str = shift;
  my $sep = shift || $COMMA;
  if ( $str =~ /\./ ) {
    $str =~ s/(?<=\d)(?=(\d{3})+\.)/,/g;
  } else {
    $str =~ s/(?<=\d)(?=(\d{3})+$)/,/g;
  }
  return $str;
}

# -------------------------------------------------------------------
sub defined_but_zero {
    return defined $_[0] && !$_[0];
}

# -------------------------------------------------------------------
sub defined_and_zero {
    return defined $_[0] && !$_[0];
}

1;
