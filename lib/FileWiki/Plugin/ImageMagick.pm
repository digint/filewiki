=head1 NAME

FileWiki::Plugin::ImageMagick - Image resource creator plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=ImageMagick(BIG,SCALED,THUMB,MINITHUMB)

    IMAGEMAGICK_FORMAT                    JPG
    IMAGEMAGICK_FORMAT_MINITHUMB          PNG
    IMAGEMAGICK_MIME_TYPE                 image/jpeg
    IMAGEMAGICK_MIME_TYPE_MINITHUMB       image/png

    IMAGEMAGICK_SCALE_THUMB               x180
    IMAGEMAGICK_SCALE_MINITHUMB           72x72
    IMAGEMAGICK_SCALE_SCALED              x720
    IMAGEMAGICK_SCALE_BIG                 2560x1440

    IMAGEMAGICK_QUALITY                   75
    IMAGEMAGICK_QUALITY_MINITHUMB         50

    IMAGEMAGICK_AUTO_ORIENT               1
    IMAGEMAGICK_STRIP                     1

=head1 DESCRIPTION

Generates images (such as thumbnails and scaled photos) using the
Image::Magick module from the ImageMagick software suite.

=head1 PLUGIN ARGUMENTS

List of image resource keys. A separate image is generated for each
resource key, with the options from the configuration variables.

=head2 Plugin Chaining

If an argument starts with the '@' character, the output file of the
given resource key is used as input file. If no such argument is
present, SRC_FILE is used as input file.

Example:

    PLUGINS=ImageMagick(@POSTER,THUMB,MINITHUMB)

This creates a THUMB and MINITHUMB resource from the target image of
the POSTER resource (i.e. $page->{RESOURCE}->{POSTER}->{TARGET_FILE}).

=head1 CONFIGURATION VARIABLES

=head2 IMAGEMAGICK_FORMAT, IMAGEMAGICK_FORMAT_<resource_key>

Specify the file format of the resource target file. If no
<resource_key> is provided, the given file format will be used as
default for all resources. The file format will also be used as the
target file suffix (e.g. ".jpg" for IMAGEMAGICK_FORMAT=JPG).

For a list of supported file formats, see
<http://www.imagemagick.org/script/formats.php>.

Example:

    IMAGEMAGICK_FORMAT                    JPG
    IMAGEMAGICK_FORMAT_MINITHUMB          PNG

This sets the image format to PNG for the MINITHUMB resource, and to
JPG for all other resources.

=head2 IMAGEMAGICK_MIME_TYPE, IMAGEMAGICK_MIME_TYPE_<resource_key>

Specify the mime type of the resource. If no <resource_key> is
provided, the given mime type will be used as default for all
resources. If no mime type is defined for a resource, the mime type is
guessed from the target file format.

Example:

    IMAGEMAGICK_MIME_TYPE                 image/jpeg
    IMAGEMAGICK_MIME_TYPE_MINITHUMB       image/png

=head2 IMAGEMAGICK_POSTFIX_<resource_key>

Filename postfix of the generated target file. Defaults to lowercase
<resource_key>.

=head2 IMAGEMAGICK_SCALE, IMAGEMAGICK_SCALE_<resource_key>

Define the geometry "<width>x<height>" of the image resource. The
<width> and <height> values specify the maximum dimensions. If either
<width> or <height> is zero, the source image is scaled
proportionally. Uses ImageMagicks "resize" function (slower than
"scale", but produces better output).

Example:

    IMAGEMAGICK_SCALE_SCALED              x720
    IMAGEMAGICK_SCALE_BIG                 2560x1440

Here, the SCALED resource is scaled proportionally to a height of
720px. The BIG resource is SCALED proportionaly to a maximum width of
2560px and a maximum height of 1440px.

=head2 IMAGEMAGICK_XSCALE, IMAGEMAGICK_XSCALE_<resource_key>

Enhanced SCALE. The ratio of the image snaps to common ratios (1:1,
3:2, 4:3, 16:9, 16:10). For portrait images, the given height becomes
width. Images smaller than the given height will not be scaled.

=head2 IMAGEMAGICK_QUALITY, IMAGEMAGICK_QUALITY_<resource_key>

Set the JPEG/MIFF/PNG compression level (0-100). If no <resource_key>
is provided, the compression level will be used as per default for all
resources.

=head2 IMAGEMAGICK_AUTO_ORIENT, IMAGEMAGICK_AUTO_ORIENT_<resource_key>

If set, adjusts the image so that its orientation is suitable for
viewing. If no <resource_key> is provided, the auto orient feature
will be enabled per default for all resources.

=head2 IMAGEMAGICK_ROTATE, IMAGEMAGICK_ROTATE_<resource_key>

Rotate the image (degrees, clockwise). If no <resource_key> is
provided, the rotate feature will be enabled per default for all
resources.

=head2 IMAGEMAGICK_TINT, IMAGEMAGICK_TINE_<resource_key>

Tint the image with color (e.g. "#FF0000", "rgb(255, 0, 0)").

=head2 IMAGEMAGICK_STRIP, IMAGEMAGICK_STRIP_<resource_key>

If set, strips image of all profiles and comments (EXIF data,
thumbnails). If no <resource_key> is provided, the strip feature will
be enabled per default for all resources.

=head2 IMAGEMAGICK_ATTRIBUTE, IMAGEMAGICK_ATTRIBUTE_<resource_key>

Set an image attribute for a resource. If no <resource_key> is
provided, the image attribute will be set for all resources. Multiple
attributes can be set using array variables (prepending the '+'
character).

Attributes are specified using the "<attribute>: <value>"
notation. For a complete list of all attributes, see
<http://www.imagemagick.org/script/perl-magick.php#set-attribute>.

Example:

    +IMAGEMAGICK_ATTRIBUTE  comment: Copyright by Snake Oil Ltd.
    +IMAGEMAGICK_ATTRIBUTE  monochrome: True

This sets the image comment to "Copyright by Snake Oil Ltd.", and
creates black and white target images.

=head1 VARIABLE PRESETS

For each resource, a new entry in the RESOURCE hash is generated:

    RESOURCE => {
      ...
      <resource_key> => {
        'NAME'        => <target image name>,
        'URI'         => <target image URI>,
        'MIME_TYPE'   => <target image mime type>,
        'TARGET_FILE' => <target image file>,
        'WIDTH'       => <effective target image width>,
        'HEIGHT'      => <effective target image height>,
        'PLUGIN_NAME' => 'FileWiki::Plugin::ImageMagick',
      }
    }

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2017 Axel Burri. All rights reserved.

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

=cut

# see: http://www.imagemagick.org/script/perl-magick.php

package FileWiki::Plugin::ImageMagick;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

use Image::ExifTool;
use Image::Size qw(imgsize);
use Image::Magick;
use File::Path qw(mkpath);

our $VERSION = "0.53";

our $MATCH_DEFAULT = '\.(bmp|gif|jpeg|jpeg2000|mng|png|psd|raw|svg|tif|tiff|gif|jpeg|jpg|png|pdf|BMP|GIF|JPEG|JPEG2000|MNG|PNG|PSD|RAW|SVG|TIF|TIFF|GIF|JPEG|JPG|PNG|PDF)$';

my $format_default = 'jpg';


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my @targets;
  my $src_file_key;
  foreach (split(/,\s*/, $args)) {
    if(/^@(.*)/) {
      $src_file_key = $1;
      next;
    }
    push @targets, $_;
  }

  my $self = {
    name             => $class,
    page_handler     => 0,
    vars_provider    => 0,
    resource_creator => 1,

    src_file_key     => $src_file_key,
    resource_targets => \@targets,
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub im_assert
{
  my $ret = shift;
  ERROR "ImageMagick function returned: $ret" if($ret);
  die($ret) if($ret);
}

sub im_cmd
{
  my $img = shift;
  my $func = shift;
  my @args = @_;
  DEBUG "Running ImageMagick method: $func(" . join(',', @args) . ")";
  my $ret = $img->$func(@args);
  ERROR "ImageMagick function returned: $ret" if($ret);
  die($ret) if($ret);
}

sub parse_attributes
{
  my $attr = shift;
  return () unless($attr);

  my %ret;
  $attr = [ $attr ] unless(ref($attr) eq 'ARRAY');
  foreach (@$attr)
  {
    unless(/^([a-z-]+):\s*(.*)/) {
      WARN "Ignoring unparseable attribute: $_";
      next;
    }
    $ret{$1} = $2;
  }
  return %ret;
}

sub create_image_resource
{
  my $self = shift;
  my $page = shift;
  my $key = shift;
  my $shared_image = shift;

  # determine target file name
  $key = uc($key);
  my $format = $page->{"IMAGEMAGICK_FORMAT_$key"} || $page->{IMAGEMAGICK_FORMAT} || $format_default;
  $format = uc($format);
  my $mime_type = $page->{"IMAGEMAGICK_MIME_TYPE_$key"} || $page->{IMAGEMAGICK_MIME_TYPE};
  my $postfix = $page->{"IMAGEMAGICK_POSTFIX_$key"} || "_" . lc($key);
  my $name = $page->{NAME} . $postfix . '.' . lc($format);
  my $target_dir = $page->{TARGET_DIR};
  my $target_file = $target_dir . $name;
  my $src_file = $page->{SRC_FILE};
  if($self->{src_file_key}) {
    if(exists($page->{RESOURCE}) && exists($page->{RESOURCE}->{$self->{src_file_key}})) {
      my $src_resource = $page->{RESOURCE}->{$self->{src_file_key}};
      $src_file = $src_resource->{TARGET_FILE};
      DEBUG "Chaining source file from target of resource \"$self->{src_file_key}\": $src_file";
      unless($src_resource->{WIDTH} && $src_resource->{HEIGHT}) {
        # make sure the chained source also has WIDTH/HEIGHT.
        # note that this is not strictly required, but is useful as it sanitizes RESOURCES passed by Plugin::ExtCmd.
        DEBUG "Adding missing WIDTH/HEIGHT from chained resource \"$self->{src_file_key}\"";
        ($src_resource->{WIDTH}, $src_resource->{HEIGHT}) = imgsize($src_file);
      }
    }
    else {
      ERROR "Resource chaining failed: no resource '$self->{src_file_key}'. Check your PLUGINS declaration: ImageMagick(@" . $self->{src_file_key} . ")";
    }
  }

  die unless($key && $format && $target_dir && $src_file);

  # check if we need to build the resources
  my ($width, $height);
  unless($self->resource_needs_rebuild($page, $target_file)) {
    ($width, $height) = imgsize($target_file);
  }

  if($width && $height)
  {
    INFO "--- $target_file";
  }
  else
  {
    if($shared_image) {
      TRACE "Reusing shared ImageMagick instance";
    } else {
      TRACE "Creating new ImageMagick instance";
      $shared_image = Image::Magick->new();
      im_assert($shared_image->Read($src_file));
    }
    my $image = $shared_image->Clone();

    # run common commands
    im_assert($image->AutoOrient()) if(defined($page->{"IMAGEMAGICK_AUTO_ORIENT_$key"}) ? $page->{"IMAGEMAGICK_AUTO_ORIENT_$key"} : $page->{"IMAGEMAGICK_AUTO_ORIENT"});
    im_assert($image->Rotate(defined($page->{"IMAGEMAGICK_ROTATE_$key"}) ? $page->{"IMAGEMAGICK_ROTATE_$key"} : $page->{"IMAGEMAGICK_ROTATE"})) if(defined($page->{"IMAGEMAGICK_ROTATE_$key"}) || defined($page->{"IMAGEMAGICK_ROTATE"}));
    im_assert($image->Strip()) if(defined($page->{"IMAGEMAGICK_STRIP_$key"}) ? $page->{"IMAGEMAGICK_STRIP_$key"} : $page->{"IMAGEMAGICK_STRIP"});

    if(my $geometry = $page->{"IMAGEMAGICK_SCALE_$key"} || $page->{"IMAGEMAGICK_SCALE"}) {
      im_assert($image->Resize(geometry => $geometry));
    }

    if(my $fill = $page->{"IMAGEMAGICK_TINT_$key"} || $page->{"IMAGEMAGICK_TINT"}) {
      im_assert($image->Tint(fill => $fill));
    }

    my $xscale = $page->{"IMAGEMAGICK_XSCALE_$key"} || $page->{"IMAGEMAGICK_XSCALE"};
    if($xscale && $xscale =~ /^([0-9]+)?x([0-9]+)$/) {
      my $xmax = $1 // "";
      my $xh = $2 // die;
      my $iw = $image->Get('width')  || die;
      my $ih = $image->Get('height') || die;
      my $ratio = ($iw > $ih) ? ($iw / $ih) : ($ih / $iw);
      my $geometry;
      if($xh > (($iw > $ih) ? $ih : $iw)) {
        INFO "IMAGEMAGICK_XSCALE_$key: no upscaling (dimension=${iw}x${ih}, xscale=${xmax}x${xh}): $target_file";
      }
      else {
        my @known_ratio = ( 1/1, 3/2, 4/3, 16/9, 16/10 );
        foreach (@known_ratio) {
          my $distance = abs($_ - $ratio);
          if($distance < 0.02) {  # hardcoded ratio distance = 0.02
            my $xw = int(($xh * $_) + 0.5);
            if($xmax && ($xw > $xmax)) {
              INFO "IMAGEMAGICK_XSCALE_$key: too wide (dimension=${iw}x${ih}), scaling to " . (($iw > $ih) ? "${xmax}x${xh}" : "${xh}x${xmax}") . ": $target_file";
            }
            else {
              DEBUG "IMAGEMAGICK_XSCALE_$key: snap to ratio=${xw}x${xh} (distance=$distance): $target_file";
              $geometry = ($iw > $ih) ? "${xw}x${xh}!" : "${xh}x${xw}!";
            }
            last;
          }
        }
        unless($geometry) {
          INFO "IMAGEMAGICK_XSCALE_$key: unknown ratio=${iw}x${ih}: $src_file";
          $geometry = ($iw > $ih) ? "${xmax}x${xh}" : "${xh}x${xmax}";
        }
        im_assert($image->Resize(geometry => $geometry));
      }
    }
    elsif($xscale) {
      die "Failed to parse XSCALE=\"$xscale\": $src_file";
    }

    # set attributes
    my %attr_quality;
    my $quality = $page->{"IMAGEMAGICK_QUALITY_$key"} || $page->{"IMAGEMAGICK_QUALITY"};
    %attr_quality = ( quality => $quality ) if($quality);

    # parse generic attributes
    # see: http://www.imagemagick.org/script/perl-magick.php#set-attribute
    my %attr_default = parse_attributes($page->{"IMAGEMAGICK_ATTRIBUTE"});
    my %attr_target  = parse_attributes($page->{"IMAGEMAGICK_ATTRIBUTE_$key"});
    my %attr = (%attr_default, %attr_target, %attr_quality);
    DEBUG "Setting attribute: $_='$attr{$_}'" foreach(keys %attr);
    # im_assert($image->Set(%attr)) if(%attr);

    # write file
    INFO ">>> $target_file";
    mkpath($target_dir);
    im_assert($image->Write(filename => $target_file, %attr));
    FileWiki::update_mtime($target_file, $page->{TARGET_MTIME});

    $width  = $image->Get('width');
    $height = $image->Get('height');
    $mime_type ||= $image->Get('mime'),
  }

  return (
    {
      NAME        => $name,
      URI         => FileWiki::get_uri($page, $name),
      MIME_TYPE   => $mime_type,
      TARGET_FILE => $target_file,
      WIDTH       => $width,
      HEIGHT      => $height,
    },
    $shared_image
   );
}


sub process_resources
{
  my $self = shift;
  my $page = shift;
  my $shared_image;
  my @filelist;

  foreach my $key (@{$self->{resource_targets}}) {
    DEBUG "Processing ImageMagick resource: $key"; INDENT 1;

    (my $resource_href, $shared_image) = $self->create_image_resource($page, $key, $shared_image);
    if($resource_href) {
      $self->add_resource($page, $key, $resource_href);
      push @filelist, $resource_href->{TARGET_FILE};
    }
    else {
      WARN "ImageMagick target failed, skipping resource";
    }
    INDENT -1;
  }
  return @filelist;
}


1;
