=head1 NAME

FileWiki::Plugin::Gallery - Gallery generator plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Gallery
    PLUGIN_GALLERY_MATCH=\.(jpg|JPG)$

    GALLERY_CONVERT_OPTIONS        -quality 75 -auto-orient
    GALLERY_SCALED_MAX_HEIGHT     720
    GALLERY_THUMB_MAX_HEIGHT      180
    GALLERY_MINITHUMB_MAX_HEIGHT  80
    GALLERY_THUMB_RATIO           16:10


=head1 DESCRIPTION

Generates image thumbs and resizes using ImageMagick's `convert`
tool. Provides EXIF information in page vars.


=head1 CONFIGURATION VARIABLES

=head2 GALLERY_CONVERT_OPTIONS

Options to be passed to ImageMagick's `convert` tool.

=head2 GALLERY_THUMB_MAX_HEIGHT, GALLERY_MINITHUMB_MAX_HEIGHT

Maximum height of the thumb and minithumb images. The maximum width is
calculated using the GALLERY_THUMB_RATIO variable.

=head2 GALLERY_THUMB_RATIO

Ratio (height/width) of the thumbs and minithumbs.

=head2 GALLERY_SCALED_MAX_HEIGHT

Maximum height of the scaled images. Note that the maximum width can
not be set for scaled images (this is because we want all the scaled
images to have the exact same height).

=head2 GALLERY_TIME_FORMAT

Time format used for GALLERY_TIME variable. See "strftime" in the
POSIX package for details about the format string.

Defaults to "%Y-%m-%d %H:%M:%S"


=head1 VARIABLE PRESETS

=head2 GALLERY_THUMB_URI, GALLERY_MINITHUMB_UIR, GALLERY_SCALED_URI

URI's pointing to the image resizes.

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

our $VERSION = "0.21";

my $match_default = '\.(bmp|gif|jpeg|jpeg2000|mng|png|psd|raw|svg|tif|tiff|gif|jpeg|jpg|png|pdf|mp4|avi|BMP|GIF|JPEG|JPEG2000|MNG|PNG|PSD|RAW|SVG|TIF|TIFF|GIF|JPEG|JPG|PNG|PDF|MP4|AVI)$';
my $video_match_default = '\.(mp4|avi|MP4|AVI)$';
my $default_image_ratio = "16:10";

our $default_time_format = '%Y-%m-%d %H:%M:%S';

sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{uc("PLUGIN_GALLERY_MATCH")} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name => $class,
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

  # calculate max width/height
  my $ratio = $page->{GALLERY_THUMB_RATIO} || $default_image_ratio;
  $ratio = ($2 / $1) if($ratio =~ m/(\d+)[:\/](\d+)/);
  $page->{GALLERY_THUMB_MAX_WIDTH}     = int($page->{GALLERY_THUMB_MAX_HEIGHT}     / $ratio);
  $page->{GALLERY_MINITHUMB_MAX_WIDTH} = int($page->{GALLERY_MINITHUMB_MAX_HEIGHT} / $ratio);
  $page->{GALLERY_SCALED_MAX_WIDTH} = "";   # NOTE: we always want the same hight here, so we do not restrict the width.

  my $video_match = $page->{GALLERY_VIDEO_MATCH} || $video_match_default;
  if($page->{SRC_FILE} =~ m/$video_match/)
  {
    #
    # process video
    #

    # fetch metadata
    DEBUG "Fetching video metadata: $page->{SRC_FILE}";
    my $cmd = "ffmpeg -i \"$page->{SRC_FILE}\" -loglevel quiet -f ffmetadata -";
    my $ret = `$cmd`;
    TRACE "$ret";
    my $metadata = {};
    foreach (split(/\n/, $ret)) {
      next if /^;/;
      /^(\w+)=(.*)/;
      $metadata->{$1} = $2;
    }
    $page->{GALLERY_VIDEO_METADATA} = $metadata;
    $page->{GALLERY_TIME} = $metadata->{creation_time};

    # convert video
    $page->{GALLERY_VIDEO_URI} = {};
    create_video_resize($page, "webm");
    create_video_resize($page, "mp4");

    # create thumbs
    $page->{GALLERY_SCALED_MAX_HEIGHT} = $page->{GALLERY_VIDEO_MAX_HEIGHT};
    my $still_image_src = create_resize($page, "ffmpeg", "SCALED");
    create_resize($page, "convert", "THUMB", $still_image_src);
    create_resize($page, "convert", "MINITHUMB", $still_image_src);
  }
  else
  {
    #
    # process image
    #

    # fetch exif data
    my $exif = Image::ExifTool->new();
    $exif->Options(Unknown => 1) ;
    $exif->Options(DateFormat => $page->{GALLERY_TIME_FORMAT} || $default_time_format);

    DEBUG "Fetching EXIF data: $page->{SRC_FILE}";
    my $infos = $exif->ImageInfo($page->{SRC_FILE});
    my %exif_hash;
    foreach (keys(%$infos)) {
      $exif_hash{$_} = { desc => $exif->GetDescription($_),
                         info => $infos->{$_} };
    }

    $page->{GALLERY_EXIF} = \%exif_hash;
    $page->{GALLERY_ORIGINAL_WIDTH} = $infos->{ImageWidth};
    $page->{GALLERY_ORIGINAL_HEIGHT} = $infos->{ImageHeight};

    # set date / time
    $page->{GALLERY_TIME} = $infos->{DateTimeOriginal};

    unless($page->{GALLERY_TIME}) {
      WARN "Invalid GALLERY_TIME (missing EXIF data): $page->{SRC_FILE}";

      #    WARN "No EXIF \"DateTimeOriginal\" found, setting date/time from MTIME: $page->{SRC_FILE}";
      #    $page->{GALLERY_DATE} = $page->{GALLERY_DATE} || time2str($page->{GALLERY_DATE_FORMAT} || $default_date_format, $page->{SRC_FILE_MTIME});
      #    $page->{GALLERY_TIME} = $page->{GALLERY_TIME} || time2str($page->{GALLERY_TIME_FORMAT} || $default_time_format, $page->{SRC_FILE_MTIME});
      #    $page->{GALLERY_DATETIME} = $page->{GALLERY_DATE} . ' ' . $page->{GALLERY_TIME};
    }

    # create thumbs
    create_resize($page, "convert", "THUMB");
    create_resize($page, "convert", "MINITHUMB");
    create_resize($page, "convert", "SCALED");
  }
}


sub create_resize
{
  my $page = shift;
  my $resize_tool = shift;
  my $type = shift;
  my $infile = shift || $page->{SRC_FILE};

  # set URI and TARGET_FILE
  my $name = $page->{NAME} . '_' . lc($type) . '.jpg';
  my $outfile  = $page->{TARGET_DIR} . $name;
  $page->{"GALLERY_${type}_URI"}         = $page->{URI_PREFIX} . $page->{URI_DIR} . $name;
  $page->{"GALLERY_${type}_TARGET_FILE"} = $outfile;

  die unless($infile && $outfile);

  if(-e $outfile) {
    DEBUG "Skipping image resize: $outfile";
  }
  else {
    INFO "Generating image resize: $outfile"; INDENT 1;
    mkpath($page->{TARGET_DIR});

    my $cmd;
    if($resize_tool eq "convert") {
      my $geometry = $page->{"GALLERY_${type}_MAX_WIDTH"} . 'x' . $page->{"GALLERY_${type}_MAX_HEIGHT"};
      my $options  = $page->{"GALLERY_CONVERT_OPTIONS"} || "";
      $cmd = "convert $options -scale $geometry \"$infile\" \"$outfile\"";
    }
    elsif($resize_tool eq "ffmpeg") {
      my $geometry = ($page->{"GALLERY_${type}_MAX_WIDTH"} || "-1") . ':' . ($page->{"GALLERY_${type}_MAX_HEIGHT"} || "-1");
      $cmd = "ffmpeg -i \"$infile\" -loglevel quiet -vframes 1 -r 1 -ss 00:00:10 -f image2 -vf scale=$geometry \"$outfile\"";
    }
    else {
      die("unsupported resize tool: $resize_tool");
    }
    DEBUG "$cmd";
    `$cmd`;
    INDENT -1;
  }
  ($page->{"GALLERY_${type}_WIDTH"}, $page->{"GALLERY_${type}_HEIGHT"}) = imgsize($outfile) ;

  return $outfile;
}


sub create_video_resize
{
  my $page = shift;
  my $type = shift;

  my $name = $page->{NAME} . '.' . $type;
  my $infile   = $page->{SRC_FILE};
  my $outfile  = $page->{TARGET_DIR} . $name;

  # set GALLERY_VIDEO_URI
  $page->{GALLERY_VIDEO_URI}->{$type} = $page->{URI_PREFIX} . $page->{URI_DIR} . $name;

  die unless($infile && $outfile);

  if(-e $outfile) {
    DEBUG "Skipping video resize: $outfile";
  }
  else {
    INFO "Generating video resize: $outfile"; INDENT 1;
    mkpath($page->{TARGET_DIR});
    my $geometry = ($page->{GALLERY_VIDEO_MAX_WIDTH} || "-1") . ':' . ($page->{GALLERY_VIDEO_MAX_HEIGHT} || "-1");
    my $options  = $page->{"GALLERY_FFMPEG_" . uc($type) . "_OPTIONS"} || die("no GALLERY_FFMPEG_" . uc($type) . "_OPTIONS provided");

    my $cmd = "ffmpeg -i \"$infile\" -loglevel quiet $options -vf scale=$geometry \"$outfile\"";
    DEBUG "$cmd";
    `$cmd`;
    INDENT -1;
  }
  ($page->{"GALLERY_${type}_WIDTH"}, $page->{"GALLERY_${type}_HEIGHT"}) = imgsize($outfile) ;

  return $outfile;
}

1;
