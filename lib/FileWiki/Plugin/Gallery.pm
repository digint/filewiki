=head1 NAME

FileWiki::Plugin::Gallery - Gallery generator plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Gallery
    PLUGIN_GALLERY_MATCH=\.(jpg|JPG)$

    GALLERY_IMAGE_TARGETS                 THUMB:jpg, MINITHUMB:jpg, SCALED:jpg, BIG:jpg

    GALLERY_IMAGE_DIMENSIONS_THUMB        0x180 4:3
    GALLERY_IMAGE_DIMENSIONS_MINITHUMB    0x80  4:3
    GALLERY_IMAGE_DIMENSIONS_SCALED       0x720
    GALLERY_IMAGE_DIMENSIONS_BIG          2560x1440

    GALLERY_IMAGE_CMD_JPG                 convert __OPTIONS__ -scale __GEOMETRY__ __INFILE__ __OUTFILE__
    GALLERY_IMAGE_CMD_JPG_OPTION_ORIENT   -auto-orient
    GALLERY_IMAGE_CMD_JPG_OPTION_QUALITY  -quality 75


=head1 DESCRIPTION

Generates user-defined images (such as thumbnails and scaled photos)
from a photo collection using ImageMagick's `convert` tool. Processes
EXIF data using Image::ExifTool and provides the results as page
variables.


=head1 CONFIGURATION VARIABLES

=head2 GALLERY_TIME_FORMAT

Time format used for GALLERY_TIME variable. See "strftime" in the
POSIX package for details about the format string.

Defaults to "%Y-%m-%d %H:%M:%S"

=head2 GALLERY_IMAGE_TARGETS

Define the image targets to be generated, of form:

    <target>:<type> [, <target>:<type>]...

Example:

    GALLERY_IMAGE_TARGETS                   THUMB:jpg, MINITHUMB:jpg, SCALED:jpg

This creates three image targets for every source file "myphoto.png":
"myphoto_thumb.jpg", "myphoto_minithumb.jpg" and "myphoto_scaled.jpg".

=head2 GALLERY_IMAGE_DIMENSIONS_<TARGET>

Define the dimensions of the transformed images to be generated. The
value specifies the maximum dimensions:

    WxH [ratio]

Example:

    GALLERY_IMAGE_DIMENSIONS_THUMB          0x180
    GALLERY_IMAGE_DIMENSIONS_MINITHUMB      0x80  4:3

The thumbs scale proportionally to a height of 180px. The minithumbs
scale proportionally to fit into 106x80px.

=head2 GALLERY_VIDEO_MATCH

Treats files matching this expression as video files. Every video file
executes all commands specified by the GALLERY_VIDEO_CMD_<TYPE>
variables, and sets the GALLERY_VIDEO variable.

=head2 GALLERY_IMAGE_CMD_<TYPE>

Specifies commands to be executed for image files. Image commands
expand the following placeholders:

 - __INFILE__   : Input file
 - __OUTFILE__  : Output file
 - __OPTIONS__  : Options specified by GALLERY_IMAGE_CMD_<TYPE>_OPTIONS_<myoption>
                  variables.
 - __GEOMETRY__ : Image geometry, computed from GALLERY_IMAGE_DIMENSIONS_<TARGET>.

Example (create resized jpg using imagemagick):

    GALLERY_IMAGE_CMD_JPG                        convert __OPTIONS__ -scale __GEOMETRY__ __INFILE__ __OUTFILE__
    GALLERY_IMAGE_CMD_JPG_OPTION_ORIENT          -auto-orient
    GALLERY_IMAGE_CMD_JPG_OPTION_QUALITY         -quality 75

=head2 GALLERY_VIDEO_CMD_<TYPE>

Specifies commands to be executed for video files. Video commands
expand the following placeholders:

 - __INFILE__  : Input file
 - __OUTFILE__ : Output file
 - __OPTIONS__ : Options specified by GALLERY_VIDEO_CMD_<TYPE>_OPTIONS_<myoption>
                 variables.

Example (create webm video):

    GALLERY_VIDEO_CMD_WEBM                       ffmpeg -y -i __INFILE__ -loglevel warning -threads 8 -copyts __OPTIONS__ __OUTFILE__
    GALLERY_VIDEO_CMD_WEBM_MIME_TYPE             video/webm
    GALLERY_VIDEO_CMD_WEBM_OPTION_SCALE          -vf scale=-1:360
    GALLERY_VIDEO_CMD_WEBM_OPTION_FORMAT         -f webm
    GALLERY_VIDEO_CMD_WEBM_OPTION_VIDEO_CODEC    -codec:v libvpx
    GALLERY_VIDEO_CMD_WEBM_OPTION_VIDEO_QUALITY  -crf 26 -cpu-used 0 -qmin 10 -qmax 42
    GALLERY_VIDEO_CMD_WEBM_OPTION_AUDIO_CODEC    -codec:a libvorbis
    GALLERY_VIDEO_CMD_WEBM_OPTION_AUDIO_BITRATE  -b:a 128k

=head2 GALLERY_SIDECAR_POSTFIX

Load additional EXIF information from sidecar files. Several file
postfixes can be specified, separated by colon (":").

Example:

    GALLERY_SIDECAR_POSTFIX  .xmp:.XMP

This will load EXIF information from "myfile.jpg.xmp" in addition to
the EXIF information in "myfile.jpg".

=head2 GALLERY_DISABLE_EXIF_WARNINGS

Disable warnings generated when EXIF data is missing (especially on
missing GALLERY_TIME)

=head1 VARIABLE PRESETS

Note:

- <TARGET>: a target listed in GALLERY_IMAGE_TARGETS

=head2 GALLERY_IMAGE_<TARGET>_URI

URI's pointing to the transformed image.

=head2 GALLERY_IMAGE_<TARGET>_NAME

File name of the transformed image, in format: "$NAME_<target>.jpg".
Note that <target> is transformed to lower case for the file name.

=head2 GALLERY_TIME

Date/Time extracted from EXIF "DateTimeOriginal" key, formatted using
GALLERY_TIME_FORMAT.

=head2 GALLERY_EXIF

Hash of all EXIF information provided by the source image. Refer to
the manual of Image::ExifTool for more informations about the EXIF
keys.

    GALLERY_EXIF={ exif_key => { desc => "Key description",
                                 info => "EXIF value"
                               }
                   exif_key...
                 }

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2012 Axel Burri. All rights reserved.

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


package FileWiki::Plugin::Gallery;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

#use Date::Format qw(time2str);
use Image::ExifTool;
use Image::Size qw(imgsize);
use File::Path qw(mkpath);

our $VERSION = "0.40";

my $match_default = '\.(bmp|gif|jpeg|jpeg2000|mng|png|psd|raw|svg|tif|tiff|gif|jpeg|jpg|png|pdf|mp4|avi|BMP|GIF|JPEG|JPEG2000|MNG|PNG|PSD|RAW|SVG|TIF|TIFF|GIF|JPEG|JPG|PNG|PDF|MP4|AVI)$';
my $video_match_default = '\.(mp4|avi|MP4|AVI)$';

our $default_time_format = '%Y-%m-%d %H:%M:%S';

sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{uc("PLUGIN_GALLERY_MATCH")} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name            => $class,
    page_handler    => 1,
    vars_provider   => 1,
    target_file_ext => 'html',
    filter => [
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub update_vars
{
  my $self = shift;
  my $page = shift;

  # set uri of original image
  if($page->{GALLERY_ORIGINAL_URI_PREFIX}) {
    my $gallery_original_uri = $page->{SRC_FILE};
    $gallery_original_uri =~ s/^$page->{BASEDIR}/$page->{GALLERY_ORIGINAL_URI_PREFIX}/;
    $page->{GALLERY_ORIGINAL_URI} = $gallery_original_uri;
  }

  # fetch exif data
  my %exif_hash;
  my $exif = Image::ExifTool->new();
  $exif->Options(Unknown => 1) ;
  $exif->Options(DateFormat => $page->{GALLERY_TIME_FORMAT} || $default_time_format);

  my @exif_files;
  if($page->{GALLERY_SIDECAR_POSTFIX}) {
    push(@exif_files, $page->{SRC_FILE} . $_) foreach (split(/:/, $page->{GALLERY_SIDECAR_POSTFIX}));
  }
  push(@exif_files, $page->{SRC_FILE});
  foreach my $exif_src (@exif_files) {
    next unless(-e $exif_src);

    DEBUG "Fetching EXIF data: $exif_src";
    $exif->ExtractInfo($exif_src);
    my $infos = $exif->GetInfo();
    my @tags = $exif->GetFoundTags();
    foreach (@tags) {
      # make sure we're in scalar context. If not, GetValue can return ARRAY in some cases.
      my $print = $exif->GetValue($_, 'PrintConv');
      my $value = $exif->GetValue($_, 'ValueConv');
      my $raw   = $exif->GetValue($_, 'Raw');
      my $desc  = $exif->GetDescription($_);

      # WARN("duplicate EXIF key: $_  (old: $exif_hash{$_}->{value}; new: $value") if exists($exif_hash{$_});
      $exif_hash{$_} = { print => $print,
                         desc  => $desc,
                         value => $value,
                         raw   => $raw,
                       };
    }
  }

  $page->{GALLERY_EXIF} = \%exif_hash;
  $page->{GALLERY_ORIGINAL_WIDTH} = $exif_hash{ImageWidth}->{value};
  $page->{GALLERY_ORIGINAL_HEIGHT} = $exif_hash{ImageHeight}->{value};

  unless($page->{GALLERY_ORIGINAL_WIDTH} && $page->{GALLERY_ORIGINAL_HEIGHT}) {
    ($page->{"GALLERY_ORIGINAL_WIDTH"}, $page->{"GALLERY_ORIGINAL_HEIGHT"}) = imgsize($page->{SRC_FILE});
  }

  # set date / time
  $page->{GALLERY_TIME} = $exif_hash{DateTimeOriginal}->{print} if(exists $exif_hash{DateTimeOriginal});

  unless($page->{GALLERY_TIME}) {
    WARN "Invalid GALLERY_TIME (missing EXIF data): $page->{SRC_FILE}" unless($page->{GALLERY_DISABLE_EXIF_WARNINGS});

    #    WARN "No EXIF \"DateTimeOriginal\" found, setting date/time from MTIME: $page->{SRC_FILE}";
    #    $page->{GALLERY_DATE} = $page->{GALLERY_DATE} || time2str($page->{GALLERY_DATE_FORMAT} || $default_date_format, $page->{SRC_FILE_MTIME});
    #    $page->{GALLERY_TIME} = $page->{GALLERY_TIME} || time2str($page->{GALLERY_TIME_FORMAT} || $default_time_format, $page->{SRC_FILE_MTIME});
    #    $page->{GALLERY_DATETIME} = $page->{GALLERY_DATE} . ' ' . $page->{GALLERY_TIME};
  }


  # Generate image thumbnails and video
  #
  # Note: we cannot create the thumbs in process_page() hook, since we
  # need the real size of the generated images in page vars.

  DEBUG "Processing gallery image/video: $self->{name}"; INDENT 1;

  my $video_match = $page->{GALLERY_VIDEO_MATCH} || $video_match_default;
  my $image_src = $page->{SRC_FILE};
  if($page->{SRC_FILE} =~ m/$video_match/)
  {
    my @videos;

    # run the GALLERY_VIDEO_CMD_* commands
    foreach my $key (keys %$page) {
      next unless($key =~ /^GALLERY_VIDEO_CMD_([A-Z0-9]+)$/);
      my $type = $1;
      my ($name, $uri, $target_file) = create_generic($page, $key, $type, "", $page->{SRC_FILE});
      my $mime_type = $page->{$key . "_MIME_TYPE"};
      WARN "Variable ${key}_MIME_TYPE is not provided: $page->{SRC_FILE}" unless($mime_type);
      push(@videos, { NAME        => $name,
                      MIME_TYPE   => $mime_type,
                      URI         => $uri,
                      TARGET_FILE => $target_file,
                    } );
    }

    if(scalar @videos) {
      # create still image
      my ($name, $uri, $target_file) = create_generic($page, "GALLERY_VIDEO_STILL_IMAGE_CMD", "JPG", "", $videos[0]->{TARGET_FILE});
      $page->{"GALLERY_VIDEO_STILL_IMAGE_NAME"} = $name;
      $page->{"GALLERY_VIDEO_STILL_IMAGE_URI"} = $uri;
      $page->{"GALLERY_VIDEO_STILL_IMAGE_TARGET_FILE"} = $target_file;
      ($page->{"GALLERY_VIDEO_STILL_IMAGE_WIDTH"}, $page->{"GALLERY_VIDEO_STILL_IMAGE_HEIGHT"}) = imgsize($target_file);

      # set still image as source for transformed image
      $image_src = $target_file;
    }
    else {
      ERROR "No videos processed (missing GALLERY_VIDEO_CMD_* variable?): $page->{SRC_FILE}";
      $image_src = "";
    }

    $page->{GALLERY_VIDEO} = \@videos;
  }


  # create thumbs
  my @image_targets = split(/\s*,\s*/, $page->{GALLERY_IMAGE_TARGETS});
  foreach my $image_target (@image_targets)
  {
    unless($image_target =~ /^([A-Z][A-Z0-9]*):\s*(\w*)$/) {
      ERROR "Invalid GALLERY_IMAGE_TARGETS declaration: expected \"<target>:<type>\", got \"$image_target\"";
      next;
    }
    my ($target, $type) = ($1, $2);

    unless($page->{"GALLERY_IMAGE_DIMENSIONS_$target"}) {
      ERROR "Missing variable: \"GALLERY_IMAGE_DIMENSIONS_$target\"";
      next;
    }

    # get/calculate max width/height for GALLERY_IMAGE_*
    if($page->{"GALLERY_IMAGE_DIMENSIONS_$target"} =~ m/(\d+)x(\d+)(\s+[\d\.:]+)?/) {
      my $w = $1;
      my $h = $2;
      my $ratio = $3 || 0;
      $ratio = ($2 / $1) if($ratio =~ m/(\d+)[:\/](\d+)/);

      if($ratio) {
        if   ($h && (not $w)) { $w = int($h / $ratio) }
        elsif($w && (not $h)) { $h = int($w * $ratio) }
      }

      ERROR "Failed to calculate max width/height for GALLERY_IMAGE_DIMENSIONS_$target=$page->{GALLERY_IMAGE_DIMENSIONS_$target}" unless($w || $h);
      TRACE "Setting GALLERY_IMAGE_${target}_MAX_WIDTH=$w, GALLERY_IMAGE_${target}_MAX_HEIGHT=$h";

      if(((not $w) || ($w > $page->{GALLERY_ORIGINAL_WIDTH})) && ((not $h) || ($h > $page->{GALLERY_ORIGINAL_HEIGHT}))) {
        WARN "Target image dimensions ($target) are larger than original image, cropping to original";
        $w = $page->{GALLERY_ORIGINAL_WIDTH};
        $h = $page->{GALLERY_ORIGINAL_HEIGHT};
      }

      # create thumbs
      if($image_src) {
        my $geometry = ($w || "") . 'x' . ($h || "");
        my $key = "GALLERY_IMAGE_CMD_" . uc($type);
        my ($name, $uri, $target_file) = create_generic($page, $key, $type, $target, $image_src, $geometry);
        $page->{"GALLERY_IMAGE_${target}_NAME"} = $name;
        $page->{"GALLERY_IMAGE_${target}_MIME_TYPE"} = $page->{$key . "_MIME_TYPE"};
        $page->{"GALLERY_IMAGE_${target}_URI"}  = $uri;
        $page->{"GALLERY_IMAGE_${target}_TARGET_FILE"} = $target_file;
        $page->{"GALLERY_IMAGE_${target}_MAX_WIDTH"} = $w;
        $page->{"GALLERY_IMAGE_${target}_MAX_HEIGHT"} = $h;
        ($page->{"GALLERY_IMAGE_${target}_WIDTH"}, $page->{"GALLERY_IMAGE_${target}_HEIGHT"}) = imgsize($target_file) ;
      }
    }
    else {
      ERROR "Invalid GALLERY_IMAGE_DIMENSIONS_$target declaration: " . $page->{"GALLERY_IMAGE_DIMENSIONS_$target"};
    }
  }

  INDENT -1;
  return $page;
}


sub exec_logged
{
  my $cmd = shift;
  my $target_dir = shift;
  DEBUG "$cmd";
  mkpath($target_dir);

  `$cmd`;
  ERROR "Command execution failed ($?): $cmd" if($?);
}


sub create_generic
{
  my $page = shift;
  my $key = shift;
  my $type = shift;
  my $target = shift;
  my $infile = shift;
  my $geometry = shift;

  my $cmd = $page->{$key};
  my $name = $page->{NAME};
  $name .= "_" . lc($target) if($target);
  $name .= '.' . lc($type);

  my $outfile = $page->{TARGET_DIR} . $name;

  # set URI and TARGET_FILE
  my $uri = $page->{URI_PREFIX} . $page->{URI_DIR} . $name;

  unless($cmd) {
    ERROR "Gallery command failed: missing variable $key";
    return ($name, $uri, $outfile);
  }

  die unless($infile && $outfile);

  if (-e $outfile) {
    DEBUG "Target file exists, skipping command ($key): $outfile";
  } else {
    INFO ">>> $outfile"; INDENT 1;
    DEBUG "Executing $key: $outfile";

    my $options = '';
    foreach (keys %$page) {
      next unless(/^${key}_OPTION_[A-Z0-9_]+$/);
      $options .= ' ' . $page->{$_};
    }
    $cmd =~ s/__INFILE__/"$infile"/;
    $cmd =~ s/__OUTFILE__/"$outfile"/;
    $cmd =~ s/__OPTIONS__/$options/;
    $cmd =~ s/__GEOMETRY__/$geometry/ if($geometry);

    exec_logged($cmd, $page->{TARGET_DIR});
    INDENT -1;
  }

  return ($name, $uri, $outfile);
}

1;
