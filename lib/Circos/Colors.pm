package Circos::Colors;

=pod

=head1 NAME

Circos::Colors - Color handling for Circos

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
our @EXPORT = qw(allocate_colors allocate_color rgb_color rgb_color_opacity rgb_color_transparency rgb_to_color);

use Carp qw( carp confess croak );
use FindBin;
use List::Util qw( max min );
use List::MoreUtils qw( uniq );
use Digest::MD5 qw(md5_hex);
use Memoize;
use Math::Round;
use Params::Validate qw(:all);
use Regexp::Common;
use Storable;
use Time::HiRes qw(gettimeofday tv_interval);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Configuration qw(%CONF);
use Circos::Debug;
use Circos::Image qw($IM $COLORS);
use Circos::Utils;

memoize("validate_rgb_list");

# -------------------------------------------------------------------
sub allocate_colors {

    return undef if ! $CONF{image}{pngmake};
    
    my $image            = shift;
    my $allocated_colors = 0;
    my $colors           = {};
    
    # scan the <colors> block and first allocate all colors
    # specified as r,g,b or r,g,b,a.
    #
    # resolution of name lookups or lists is avoided at this point

    start_timer("colordefinitions");
    for my $color_name ( sort keys %{ $CONF{colors} } ) {
	if(ref $CONF{colors}{$color_name} eq "ARRAY") {
	    my @unique_definitions = uniq @{$CONF{colors}{$color_name}};
	    if(@unique_definitions == 1) {
		printwarning("The color [$color_name] has multiple identical definitions: ".join(" ",@unique_definitions));
		$CONF{colors}{$color_name} = $unique_definitions[0];
	    } else {
		confess "The color [$color_name] has multiple distinct definitions: ".join(" ",@unique_definitions)." Please use only one of these.";
	    }
	} elsif( ref $CONF{colors}{$color_name}) {
	    confess "The color [$color_name] is not defined correctly. Saw a data structure instead of a simple color assignment.";
	}
	my $color_definition = $CONF{colors}{$color_name};
	if(validate_rgb($color_definition)) {
	    printdebug_group("color","parsing_color RGB",$color_definition);
	    allocate_color($color_name,$color_definition,$colors,$image);
	} elsif (validate_hsv($color_definition)) {
	    my @hsv = validate_hsv($color_definition);
	    use Graphics::ColorObject;
	    my $color = Graphics::ColorObject->new_HSV(\@hsv);
	    my $rgb_text = join(",",@{$color->as_RGB255});
	    printdebug_group("color","parsing_color HSV",$color_definition,"RGB",$rgb_text);
	    allocate_color($color_name,$rgb_text,$colors,$image);
	}
    }
    stop_timer("colordefinitions");

    # now resolve name lookups
    start_timer("colorlookups");
    for my $color_name ( sort keys %{ $CONF{colors} } ) {
	my $color_definition = $CONF{colors}{$color_name};
	# if this color has already been allocated, skip it
	next if exists $colors->{$color_name};
	my %lookup_seen;
	while( exists $CONF{colors}{$color_definition} ) {
	    printdebug_group("color","colorlookup",$color_definition);
	    if($lookup_seen{$color_definition}++) {
		confess "You have a circular color definition in your <color> block involving color [$color_definition] and [".$CONF{colors}{$color_definition}."]. While you can define one color in terms of another (e.g., red=255,0,0 and favourite=red), you must avoid loops (e.g. red=favourite and favourite=red)";
	    }
	    $colors->{$color_name} = $colors->{$color_definition};
	    printdebug_group("color","colorlookupassign",$color_name,$color_definition,$CONF{colors}{$color_definition});
	    $color_definition = $CONF{colors}{$color_definition};
	}
    }
    stop_timer("colorlookups");

    # automatic transparent colors
    start_timer("colortransparency");
    create_transparent_colors($colors,$image);
    stop_timer("colortransparency");

    # now resolve lists - employ caching since this can be slow (2-5 seconds);

    start_timer("colorlists");
    my $cache_file = "/tmp/circos.colorlist.dat";
    my $allocated_color_list = [keys %$colors];
    my $list_cache;
    my $cache_ok;
    if(-e $cache_file) {
	start_timer("colorcache");
	printdebug_group("cache","colorlist cache",$cache_file,"found");
	if (-M $cache_file < -M $CONF{configfile}) {
	    printdebug_group("cache","colorlist cache",$cache_file,"useable - more recent than configfile");
	    # cache file younger than config file, read cache
	    eval {
		$list_cache = retrieve($cache_file);
	    };
	    if($@) {
		printwarning("problem reading color cache file [$cache_file]");
		$cache_ok = 0;
	    } else {
		printdebug_group("cache","colorlist cache",$cache_file,"read in");
		my $target_hash = Digest::MD5::md5_hex(join("", sort keys %{$CONF{colors}}));
		if($list_cache->{colorhash} eq $target_hash) {
		    printdebug_group("cache","colorlist hash",$target_hash,"matches - using file");
		    $cache_ok = 1;
		} else {
		    printdebug_group("cache","colorlist hash",$target_hash,"does not match - colors changed? - recomputing file");
		}
	    }
	} else {
		printdebug_group("cache","colorlist cache",$cache_file,"older than configfile - recreating cache");
	}
	stop_timer("colorcache");
    } else {
	printdebug_group("cache","colorlist cache",$cache_file,"not found");
    }
    if(! $cache_ok) {
	# create cache
	$list_cache->{colorhash} = Digest::MD5::md5_hex(join("", sort keys %{$CONF{colors}}));
	printdebug_group("cache","creating colorlist cache, hash",$list_cache->{colorhash});
	for my $color_name ( sort keys %{ $CONF{colors} } ) {
	    # skip if this color has already been allocated
	    next if exists $colors->{$color_name};
	    my @color_definitions = str_to_list($CONF{colors}{$color_name});
	    my @match_set;
	    for my $color_definition (@color_definitions) {
		# do a very quick match to narrow down the colors with fast grep()
		my $rx = $color_definition;
		if($rx =~ /rev\((.+)\)/) {
		    $rx  = $1;
		}
		my @early_matches = grep($_ =~ /$rx/, @$allocated_color_list);
		my @matches;
		# now do a full match, including sorting results
		if(@early_matches) {
		    @matches       = sample_list($color_definition,\@early_matches); #$allocated_color_list);
		}
		if(! @matches) {
		    confess "The color list [$color_name] included a definition [$color_definition] that does not match any previously defined color.";
		}
		push @match_set, @matches;
	    }
	    $list_cache->{list2color}{$color_name} = \@match_set;
	    printdebug_group("color","colorlist",$color_name,@match_set);
	}
	# store cache
	eval { 
	    printdebug_group("cache","writing to colorlist cache file [$cache_file]");
	    store($list_cache,$cache_file);
	};
	if($@) {
	    printwarning("could not write to color list cache file [$cache_file] - store() gave error");
	    printinfo($@);
	} else {
	    if(-e $cache_file) {
		printdebug_group("cache","wrote to colorlist cache file [$cache_file]");
	    } else {
		printwarning("could not write to color list cache file [$cache_file]");
	    }
	}
    }
    for my $color (keys %{$list_cache->{list2color}}) {
	$colors->{$color} = $list_cache->{list2color}{$color};
	push @$allocated_color_list, $color;
    }
    stop_timer("colorlists");
    return $colors;
}
 

# -------------------------------------------------------------------
sub rgb_color_opacity {
  # Returns the opacity of a color, based on its name. Colors with a
  # trailing _aNNN have a transparency level in the range
  # 0..auto_alpha_steps. 
  my $color = shift;
  return 1 if ! defined $color;
  if ( $color =~ /(.+)_a(\d+)/ ) {
    unless ( $CONF{image}{auto_alpha_colors}
	     && $CONF{image}{auto_alpha_steps}
	   ) {
      die "you are trying to process a transparent color ($color) ",
	"but do not have auto_alpha_colors or auto_alpha_steps defined";
    }
    my $color_root = $1;
    my $opacity    = 1 - $2 / (1+$CONF{image}{auto_alpha_steps});
  } else {
    return 1;
  }
}


# -------------------------------------------------------------------
sub allocate_color {
    my ($name,$definition,$colors,$image) = @_;
    my @rgb = validate_rgb($definition);
    my $idx;
    printdebug_group("color","allocate_color 0",@rgb);
    if ( @rgb == 3 ) {
	if($name =~ /.+_a\d+$/) {
	    confess "You are trying to allocate color [$name] with definition [$definition], but names ending in _aN are reserved for colors with transparency.";
	}
	eval {
	    my $color_index = $image->colorExact(@rgb);
	    if ( $color_index == -1 ) {
		$colors->{$name} = $image->colorAllocate(@rgb);
	    } else {
		$colors->{$name} = $color_index;
	    }
	};
	printdebug_group("color","allocate_color 1",@rgb,$image->colorExact(@rgb));
	if ($@) {
	    confess "Could not allocate color [$name] with definition [$definition]. $@";
	}
    } elsif ( @rgb == 4 ) {
	if($rgb[3] < 0 || $rgb[3] > 127) {
	    confess "Alpha value of $rgb[3] cannot be used. Please use a range 0-127.";
	}
	$rgb[3] *= 127 if $rgb[3] < 1;
	eval {
	    printdebug_group("color","allocate_color 2",@rgb);
	    $colors->{$name} = $image->colorAllocateAlpha(@rgb);
	};
	if ($@) {
	    confess "Could not allocate color [$name] with definition [$definition]. $@";
	}
    }
    printdebug_group("color","allocate_color","idx",$colors->{$name},$name,@rgb,"now have",int(keys %$colors),"colors");
}

# -------------------------------------------------------------------
sub create_transparent_colors {
    # Automatically allocate colors with alpha values, if asked for.
    # The number of steps is determined by auto_alpha_steps in the
    # <image> block
    # Colors with alpha values have names COLOR_aN for N=1..num_steps
    # The alpha value (out of max 127) for step i is 127*i/(num_steps+1)
    #
    # For example, if the number of steps is 5, then for the color
    # chr19=153,0,204, the follow additional 5 colors will be
    # allocated (see full list in lines with 'auto_alpha_color' with -debug).
    #
    # Now add automatic transparenc levels to all the defined colors
    # using _aN suffix
    my ($colors,$image) = @_;
    return unless $CONF{image}{auto_alpha_colors};
    my @c = keys %$colors;
    for my $color_name (@c) {
	# if this color is already transparent, skip it
	next if $color_name =~ /.*_a\d+$/;
	my @rgb = $image->rgb( $colors->{$color_name} );
	# provide _a0 synonym
	$colors->{ sprintf("%s_a0",$color_name) } = $colors->{ $color_name };
	for my $i ( 1 .. $CONF{image}{auto_alpha_steps} ) {
	    my $alpha = round( 127 * $i / ( $CONF{image}{auto_alpha_steps} + 1 ) );
	    my $color_name_alpha = $color_name . "_a$i";
	    printdebug_group("color","allocate","auto_alpha_color",$color_name_alpha,@rgb,$alpha);
	    allocate_color($color_name_alpha,[@rgb,$alpha],$colors,$image);
	}
    }
}

sub validate_rgb_list {
  my @rgb = @_;
  my $n = @rgb;
  if($n == 3 || $n == 4) {
    if(grep($_ =~ /$RE{num}{int}/ 
	    &&
	    $_ >= 0 
	    &&
	    $_ <= 255, @rgb) == $n) {
      return @rgb;
    }
  }
  return undef;
}

sub validate_hsv {
    my ($definition,$strict) = @_;
    if($definition =~ /hsv\s*\(\s*(.+)\s*\)/i) {
	my $hsv_list = $1;
	my @hsv = str_to_list($hsv_list);
	if(@hsv) {
	    return @hsv;
	} else {
	    if($strict) {
		my $error = "HSB Color definition [$definition] is not in the correct format. You must use h,s,v (e.g. 60,1,0.5) or h,s,v,a (e.g. 0,1,0.5,100), where a is the alpha channel. h is in the range 0-360 , s,v 0-1 and alpha 0-127.";
		confess $error;
	    } else {
		return undef;
	    }
	}
    } else {
	return undef;
    }
}

sub validate_rgb {
    my ($definition,$strict) = @_;
    if($definition =~ /^\s*\d+\s*,\s*\d+\s*,\s*\d+\s*(,\s*\d+)?$/ || ref $definition eq "ARRAY") {
	my @rgb = ref $definition eq "ARRAY" ? @$definition : str_to_list($definition);
	#@rgb    = validate_rgb_list(@rgb);
	if(@rgb) {
	    return @rgb;
	} else {
	    if($strict) {
		my $error = "Color definition [$definition] is not in the correct format. You must use r,g,b (e.g. 255,10,50) or r,g,b,a (e.g. 255,10,50,100), where a is the alpha channel. r,g,b values must be 0-255 and alpha 0-127.";
		confess $error;
	    } else {
		return undef;
	    }
	}
    } else {
	#printinfo("fail rgb",$definition);
	return undef;
    }
}

# -------------------------------------------------------------------
sub rgb_color_transparency {
  my $color = shift;
  return 1 - rgb_color_opacity($color);
}

# -------------------------------------------------------------------
sub rgb_color {
  my $color = shift;
  #confess if ! defined $color;
  return undef if ! defined $color;
  if ( $color =~ /(.+)_a(\d+)/ ) {
    my $color_root = $1;
    return rgb_color($color_root);
  } else {
    return undef unless defined $color && exists $CONF{colors}{$color};
    my $colordef = $CONF{colors}{$color};
    if($CONF{colors}{$colordef}) {
	return rgb_color($colordef);
    }
    my @rgb = split( $COMMA, $colordef );
    return @rgb;
  }
}

sub rgb_to_color {
    my @rgb = @_;
    for my $color (keys %$COLORS) {
	next if $color =~ /_a\d+$/;
	my @crgb = $IM->rgb( fetch_color($color) );
	if($rgb[0] == $crgb[0] &&
	   $rgb[1] == $crgb[1] &&
	   $rgb[2] == $crgb[2]) {
	    return $color;
	}
    }
    confess "There was no color defined with RGB value ".join(",",@rgb);
}

1;
