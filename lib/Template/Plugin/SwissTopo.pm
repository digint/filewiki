package Template::Plugin::SwissTopo;

use strict;
use warnings;

use base qw( Template::Plugin );

use HTML::Entities;
use FileWiki::Logger;

our $VERSION = "0.50";

=head1 NAME

Template::Plugin::SwissTopo - SwissTopo plugin for Template Toolkit

=head1 SYNOPSIS

Usage in Template:

  [% USE SwissTopo %]

  [% SwissTopo.URL( lat => $lat, long => $long, zoom => 5, crosshair => "cross" ) %]


=head1 DESCRIPTION

Provides URL to SwissTopo map L<http://map.geo.admin.ch>, as well as
approximate conversion functions from WGS-84 (world latitude /
longitude) to CH-1903 (swiss coordinate system).

=head1 METHODS

=head2 URL

Generate a SwissTopo URL.

Arguments:

 - lat:       WGS-84 latitude (mandatory)
 - long:      WGS-84 longitude (mandatory)
 - zoom:      zoom factor [0..13], defaults to 8
 - crosshair: draw crosshair. supported values: "cross", "circle", "bowl" and "point"

Example:

  [% SwissTopo.URL( $lat, $long, "cross" ) %]

=back

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2015 Axel Burri. All rights reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 SEE ALSO

Swiss map projections:

L<http://www.swisstopo.admin.ch/internet/swisstopo/en/home/topics/survey/sys/refsys/projections.html>

Scripts provided by SwissTopo:

L<http://www.swisstopo.admin.ch/internet/swisstopo/en/home/products/software/products/skripts.html>

Template Toolkit Plugin Documentation:

L<http://www.template-toolkit.org/docs/modules/Template/Plugin.html>

=cut


sub new {
  my ($class, $context, @params) = @_;

  bless {
    _CONTEXT => $context,
  }, $class;
}


# Convert DEC angle to SEX DMS
sub DECtoSEX
{
  my $angle = shift;

  # Extract DMS
  my $deg = $angle;
  my $min = ($angle-$deg)*60;
  my $sec = ((($angle-$deg)*60)-$min)*60;

  # Result in degrees sex (dd.mmss)
  return $deg + $min/100 + $sec/10000;
}

# Convert Degrees angle to seconds
sub DEGtoSEC
{
  my $angle = shift;

  # Extract DMS
  my $deg = $angle;
  my $min = ($angle-$deg)*100;
  my $sec = ((($angle-$deg)*100) - $min) * 100;

  # Result in degrees sex (dd.mmss)
  return $sec + $min*60 + $deg*3600;
}

# Convert WGS lat/long (degrees dec) to CH y
sub WGStoCHy
{
  my $lat = shift;
  my $long = shift;

  # Converts degrees dec to sex
  $lat = DECtoSEX($lat);
  $long = DECtoSEX($long);

  # Converts degrees to seconds (sex)
  $lat = DEGtoSEC($lat);
  $long = DEGtoSEC($long);

  # Axiliary values (% Bern)
  my $lat_aux = ($lat - 169028.66)/10000;
  my $long_aux = ($long - 26782.5)/10000;

  # Process Y
  my $y = 600072.37
     + 211455.93 * $long_aux
     -  10938.51 * $long_aux * $lat_aux
     -      0.36 * $long_aux * $lat_aux**2
     -     44.54 * $long_aux**3;

  return $y;
}

# Convert WGS lat/long (degrees dec) to CH x
sub WGStoCHx {
  my $lat = shift;
  my $long = shift;

  # Converts degrees dec to sex
  $lat = DECtoSEX($lat);
  $long = DECtoSEX($long);

  # Converts degrees to seconds (sex)
  $lat = DEGtoSEC($lat);
  $long = DEGtoSEC($long);

  # Axiliary values (% Bern)
  my $lat_aux = ($lat - 169028.66)/10000;
  my $long_aux = ($long - 26782.5)/10000;

  # Process X
  my $x = 200147.07
     + 308807.95 * $lat_aux
     +   3745.25 * $long_aux**2
     +     76.63 * $lat_aux**2
     -    194.56 * $long_aux**2 * $lat_aux
     +    119.79 * $lat_aux**3;

  return $x;
}

# Convert CH y/x to WGS lat
sub CHtoWGSlat {
  my $x = shift;
  my $y = shift;

  # Converts militar to civil and  to unit = 1000km
  # Axiliary values (% Bern)
  my $y_aux = ($y - 600000)/1000000;
  my $x_aux = ($x - 200000)/1000000;

  # Process lat
  my $lat = 16.9023892
       +  3.238272 * $x_aux
       -  0.270978 * $y_aux**2
       -  0.002528 * $x_aux**2
       -  0.0447   * $y_aux**2 * $x_aux
       -  0.0140   * $x_aux**3;

  # Unit 10000" to 1 " and converts seconds to degrees (dec)
  $lat = $lat * 100/36;

  return $lat;
}

# Convert CH y/x to WGS long
sub CHtoWGSlong {
  my $x = shift;
  my $y = shift;

  # Converts militar to civil and  to unit = 1000km
  # Axiliary values (% Bern)
  my $y_aux = ($y - 600000)/1000000;
  my $x_aux = ($x - 200000)/1000000;

  # Process long
  my $long = 2.6779094
        + 4.728982 * $y_aux
        + 0.791484 * $y_aux * $x_aux
        + 0.1306   * $y_aux * $x_aux**2
        - 0.0436   * $y_aux**3;

  # Unit 10000" to 1 " and converts seconds to degrees (dec)
  $long = $long * 100/36;

  return $long;
}


sub URL
{
  my $self = shift;
  my $args = shift;
  my $long = $args->{long};
  my $lat = $args->{lat};
  my $crosshair = $args->{crosshair} || "bowl";
  my $zoom = $args->{zoom} // 8;
  my $bg_layer = $args->{bg_layer} || "ch.swisstopo.pixelkarte-farbe";

  unless(defined($long) && defined($lat)) {
    ERROR "SwissTopo URL: missing arguments: lat/long";
    return "";
  }

  TRACE "Creating SwissTopo URL from coordinates: [$lat, $long]";

  # <http://help.geo.admin.ch/?id=54&lang=en>
  my $url = "http://map.geo.admin.ch/";
  $url .= "?X=" . sprintf("%.2f", WGStoCHx($lat, $long));
  $url .= "&Y=" . sprintf("%.2f", WGStoCHy($lat, $long));
  $url .= "&zoom=" . $zoom;
  $url .= "&crosshair=" . $crosshair;
  $url .= "&lang=en";
  $url .= "&bgLayer=" . $bg_layer;
#  $url .= "&topic=ech";

  return encode_entities($url);
}

1;
