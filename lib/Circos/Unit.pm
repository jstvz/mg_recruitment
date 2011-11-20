package Circos::Unit;

=pod

=head1 NAME

Circos::Unit - utility routines for units in Circos

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
our @EXPORT = qw(unit_fetch unit_validate unit_fetch unit_split unit_strip unit_test unit_convert unit_parse);

use Carp qw( carp confess croak );
use FindBin;
use Params::Validate qw(:all);
use Regexp::Common;

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration qw(%CONF $DIMS);
use Circos::Constants;
use Circos::Debug;

use Memoize;

# -------------------------------------------------------------------
sub unit_fetch {
  # Return a value's unit, with sanity checks. The unit fetch is the
  # basic unit access function and it should be the basis for any
  # other unit access wrappers. This is the only function that
  # checks against a list of acceptable units.
  #
  # Returns the value of units_nounit if the value has no unit
  # (i.e., bare number)
  #
  # Returns undef if the value string does not end in one of the
  # valid unit types
  #
  # If you just want to test the sanity of a value's format, call
  # unit_fetch in void context

  my ($value,$param) = @_;

  if ( !$CONF{units_ok} ) {
    confess "The parameter [$param] value of units_ok parameter is ",
      "not defined. Try setting it to units_ok=bupr";
  }

  if ( !$CONF{units_nounit} ) {
    confess "The parameter [$param] value of units_nounit parameter ",
      "is not defined. Try setting it to units_nounit=n";
  }

  if ( $value =~ /([$CONF{units_ok}])$/o ) {
    return $1;
  } elsif ( $value =~ /\d$/o ) {
    return $CONF{units_nounit};
  } else {
    confess
      "The parameter [$param] value [$value] is incorrectly formatted.";
  }
}

# -------------------------------------------------------------------
sub unit_validate {
  # Verify that a value's unit is one out of a provided list
  #
  # potential units are
  #
  # r : relative
  # p : pixel
  # u : chromosome unit (defined by chromosomes_unit parameter)
  # b : bases, or whatever your natural unit of distance is along the ideogram
  # n : no unit; value is expected to end in a digit
  #
  # If called without a list of acceptable units, unit_validate returns
  # the value if it is correctly formatted (i.e., an acceptable unit is found)
  # stripped of its unit

  my ( $value, $param, @unit ) = @_;
  croak "not units provided" unless @unit;

  # unit_fetch will die if $value isn't correctly formatted
  my $value_unit = unit_fetch( $value, $param );
  if ( grep( $_ eq $value_unit, @unit ) ) {
    return $value;
  } else {
    confess "The parameter [$param] value [$value] does not have ",
      "the correct unit [saw $value_unit], which should be one of ",
        join( $COMMA, @unit );
  }
}

# -------------------------------------------------------------------
sub unit_split {
  # Separate the unit from the value, and return the unit-less
  # number and the unit as a list
    my ($value,$param) = @_;
    my $unit         = unit_fetch( $value, $param );
    my $value_nounit = unit_strip( $value, $param );
    return ( $value_nounit, $unit );
}

# -------------------------------------------------------------------
sub unit_strip {
  # Remove the unit from a value and return the unit-less value
  my $value = shift;
  my $param = shift;
  my $unit  = unit_fetch($value);
  $value =~ s/$unit$//;

  return $value;
}

# -------------------------------------------------------------------
sub unit_test {
  # Verify that a unit is acceptable. If so, return the unit, otherwise
  # die.
  my $unit = shift;
  if ( $unit =~ /[$CONF{units_ok}]/o || $unit eq $CONF{units_nounit} ) {
    return $unit;
  } else {
    confess "Unit [$unit] fails format check.";
  }
}

# -------------------------------------------------------------------
sub unit_convert {
    # Convert a value from one unit to another.
    start_timer("unitconvert");
    $CONF{debug_validate} && validate(
	@_,
	{
            from    => { type => SCALAR },
            to      => { type => SCALAR },
            factors => { type => HASHREF, optional => 1 },
	}
	);
    my %params = @_;
    start_timer("unitconvert_delegate");
    my ( $value, $unit_from ) = unit_split( $params{from} );
    my $unit_to = unit_test( $params{to} );
    stop_timer("unitconvert_delegate");
    my $factors = $params{factors};
    
    start_timer("unitconvert_decision");
    my $return;
    if ( $factors->{ $unit_from . $unit_to } ) {
	$return = $value * $factors->{ $unit_from . $unit_to };
    } elsif ( $factors->{ $unit_to . $unit_from } ) {
	$return = $value * 1 / $factors->{ $unit_from . $unit_to };
    } elsif ( $unit_to eq $unit_from ) {
	$return = $value;
    } else {
	croak "cannot convert unit [$unit_from] to [$unit_to] - no conversion factor supplied";
    }
    stop_timer("unitconvert_decision");
    stop_timer("unitconvert");
    return $return;
}

# -------------------------------------------------------------------
sub unit_parse {
    # Parses a variable value that contains units. The value can be a single
    # value like
    #
    # 0.1r
    #
    # or an arithmetic expression
    #
    # TERM +/- TERM +/- TERM ...
    #
    # where TERM is one of
    #
    # 1. single value with any supported unit
    # 2. the string "dims(a,b)" for some parameters a,b
    
    start_timer("unitparse");
    my $expression = shift;
    my $ideogram   = shift;
    my $side       = shift;
    my $relative   = shift;
    
    printdebug_group("unit","parse",$expression,$side,$relative);
    if(! defined $expression) {
	stop_timer("unitparse");
	return undef;
    }
    
    my $radius_flag;
    if ( defined $side ) {
	if ( $side eq $DASH || !$side || $side =~ /inner/i ) {
	    $radius_flag = "radius_inner";
	} elsif ( $side eq $PLUS_SIGN || $side == 1 || $side =~ /outer/i ) {
	    $radius_flag = "radius_outer";
	}
    }
    
    if ($ideogram) {
	$expression =~ s/ideogram,/ideogram,$ideogram->{tag},/g;
    } else {
	$expression =~ s/ideogram,/ideogram,default,/g;
    }
    
    while ( $expression =~ /(dims\(([^\)]+)\))/g ) {
	my $string = $1;
	my $hash   = "\$" . $string;
	my @args   = split( $COMMA, $2 );
	
	#printinfo("dims",$string,"args",@args);
	$hash = sprintf( "\$DIMS->%s",
			 join( $EMPTY_STR, map { sprintf( "{'%s'}", $_ ) } @args ) );
	
	#printdumper($DIMS->{ideogram}{default});
	my $hash_value = eval $hash;
	confess "dimension [$hash] is not defined in expression $expression"
	    if !defined $hash_value;
	$expression =~ s/\Q$string\E/$hash_value/g;
    }
    
    while ( $expression =~ /([\d\.]+[$CONF{units_ok}])/g ) {
	my $string = $1;
	my ( $value, $unit ) = unit_split($string);
	my $value_converted;
	
	if ( $unit eq "u" ) {
	    
	    # convert from chromosome units to bases
	    $value_converted = unit_convert(
		from    => $string,
		to      => "b",
		factors => { ub => $CONF{chromosomes_units} }
		);
	} else {
	    
	    # convert from relative or pixel to pixel
	    my $rpfactor;
	    my $tag = $ideogram ? $ideogram->{tag} : "default";
	    #printdumper($ideogram) if $ideogram->{chr} eq "hs1";
	    if ( $value < 1 ) {
		$rpfactor = $relative
		    || $DIMS->{ideogram}{$tag}{ $radius_flag || "radius_inner" };
	    } else {
		$rpfactor = $relative
		    || $DIMS->{ideogram}{$tag}{ $radius_flag || "radius_outer" };
	    }
	    $value_converted = unit_convert(
		from    => $string,
		to      => "p",
		factors => { rp => $rpfactor }
		);
    }
	
	$expression =~ s/$string/$value_converted/;
    }
    
    $expression = eval $expression;
    
    stop_timer();#"unitparse");
    return $expression;
}

1;
