package Circos::Constants;

=pod

=head1 NAME

Circos::Constants - Constants for Circos

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

use strict;
use warnings;

use base 'Exporter';
use Readonly;

Readonly our $APP_NAME   => 'circos';
Readonly our $CARAT      => q{^};
Readonly our $COLON      => q{:};
Readonly our $COMMA      => q{,};
Readonly our $DASH       => q{-};
Readonly our $DEG2RAD    => 0.0174532925;
Readonly our $DEGRANGE   => 360;
Readonly our $DOLLAR     => q{$};
Readonly our $EMPTY_STR  => q{};
Readonly our $EQUAL_SIGN => q{=};
Readonly our $PI         => 3.141592654;
Readonly our $TWOPI      => 6.283185307;
Readonly our $PIPE       => q{|};
Readonly our $PLUS_SIGN  => q{+};
Readonly our $RAD2DEG    => 57.29577951;
Readonly our $SEMICOLON  => q{;};
Readonly our $SPACE      => q{ };

our @EXPORT = qw($APP_NAME $CARAT $COLON $COMMA $DASH $DEG2RAD $DEGRANGE $DOLLAR $EMPTY_STR $EQUAL_SIGN $PI $PIPE $PLUS_SIGN $RAD2DEG $SEMICOLON $SPACE $TWOPI);

1;
