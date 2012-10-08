=head1 NAME

FileWiki::Plugin::Gallery - Gallery generator plugin for FileWiki

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

use Date::Format qw(time2str);
use File::Spec::Functions qw(splitpath);
use Image::ExifTool;
use Image::Size qw(imgsize);
use File::Path qw(mkpath);

our $VERSION = "0.20";

my $match_default = '\.(jpg|JPG|jpeg|JPEG)$';
my $default_image_ratio = "16:10";

# TODO: orientation, subject distance, use these
my @exif_tags = qw( Make
                    Model
                    ColorSpaceData
                    Flash
                    ShutterSpeedValue
                    DateCreated
                 );

our $default_date_format = '%x';
our $default_time_format = '%X';

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
#      \&gallery_create_thumb,
#      \&gallery_create_minithumb,
#      \&gallery_create_scaled,
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

  # set thumb information
  my $thumb_name = $page->{NAME} . '_thumb.jpg';
  my $minithumb_name = $page->{NAME} . '_minithumb.jpg';
  my $scaled_name = $page->{NAME} . '_scaled.jpg';
  my (undef, $target_dirname, undef) = splitpath($page->{TARGET_FILE});
  my (undef, $uri_dirname, undef) = splitpath($page->{URI});

  $page->{GALLERY_THUMB_TARGET_FILE}     = $target_dirname . $thumb_name;
  $page->{GALLERY_THUMB_URI}             = $uri_dirname    . $thumb_name;
  $page->{GALLERY_MINITHUMB_TARGET_FILE} = $target_dirname . $minithumb_name;
  $page->{GALLERY_MINITHUMB_URI}         = $uri_dirname    . $minithumb_name;
  $page->{GALLERY_SCALED_TARGET_FILE}    = $target_dirname . $scaled_name;
  $page->{GALLERY_SCALED_URI}            = $uri_dirname    . $scaled_name;

  # set uri of original image
  my $gallery_original_uri = $page->{SRC_FILE};
  $gallery_original_uri =~ s/^$page->{BASEDIR}/$page->{GALLERY_ORIGINAL_URI_PREFIX}/;
  $page->{GALLERY_ORIGINAL_URI} = $gallery_original_uri;

  # set defaults
  unless($page->{GALLERY_TITLE})
  {
    my $title_match = $page->{GALLERY_DEFAULT_PAGE_TITLE};
    my $title = $page->{SRC_FILE_NAME};
    if($title_match)
    {
      if($title =~ /$title_match/) {
        $title = $1;
        die "Bad match expression: $title_match" unless $title;
      }
    }
    if($page->{GALLERY_TITLE_MATCH} && $page->{GALLERY_TITLE_REPLACE}) {
      $title =~ s/$page->{GALLERY_TITLE_MATCH}/$page->{GALLERY_TITLE_REPLACE}/g;
    }
    DEBUG "Setting page title: $title";
    $page->{GALLERY_TITLE} = $title ;
  }

  # fetch exif data
  my $exif = Image::ExifTool->new();
  $exif->Options(Unknown => 1) ;
  $exif->Options(DateFormat => "%Y-%m-%d %H:%M:%S"); # TODO

  DEBUG "Fetching EXIF data: $page->{SRC_FILE}";
  my $infos = $exif->ImageInfo($page->{SRC_FILE});
  my @final;
  foreach (keys(%$infos)) {
    push @final, [ $_, $exif->GetDescription($_), $infos->{$_} ];
  }

  $page->{GALLERY_EXIF} = \@final;
  $page->{GALLERY_ORIGINAL_WIDTH} = $infos->{ImageWidth};
  $page->{GALLERY_ORIGINAL_HEIGHT} = $infos->{ImageHeight};

  # set date / time
  my $date = $page->{GALLERY_DATE};
  my $time = $page->{GALLERY_TIME};
  if($infos->{DateTimeOriginal}) {
    $date = $1 if($infos->{DateTimeOriginal} =~ m/(\S+)\s+\S+/);
    $time = $1 if($infos->{DateTimeOriginal} =~ m/\S+\s+(\S+)/);
  }
  $page->{GALLERY_DATETIME} = $infos->{DateTimeOriginal};
  $page->{GALLERY_DATE} = $page->{GALLERY_DATE} || $date;
  $page->{GALLERY_TIME} = $page->{GALLERY_TIME} || $time;

  unless($page->{GALLERY_DATE} && $page->{GALLERY_TIME}) {
    # fallback, no EXIF found
    WARN "No EXIF \"DateTimeOriginal\" found, setting date/time from MTIME: $page->{SRC_FILE}";
    $page->{GALLERY_DATE} = $page->{GALLERY_DATE} || time2str($page->{GALLERY_DATE_FORMAT} || $default_date_format, $page->{SRC_FILE_MTIME});
    $page->{GALLERY_TIME} = $page->{GALLERY_TIME} || time2str($page->{GALLERY_TIME_FORMAT} || $default_time_format, $page->{SRC_FILE_MTIME});
    $page->{GALLERY_DATETIME} = $page->{GALLERY_DATE} . ' ' . $page->{GALLERY_TIME}; # TODO: format
  }


  # calculate max width/height
  my $ratio = $page->{GALLERY_THUMB_RATIO} || $default_image_ratio;
  $ratio = ($2 / $1) if($ratio =~ m/(\d+)[:\/](\d+)/);
  $page->{GALLERY_THUMB_MAX_WIDTH}     = int($page->{GALLERY_THUMB_MAX_HEIGHT}     / $ratio);
  $page->{GALLERY_MINITHUMB_MAX_WIDTH} = int($page->{GALLERY_MINITHUMB_MAX_HEIGHT} / $ratio);
#  $page->{GALLERY_SCALED_MAX_WIDTH}    = int($page->{GALLERY_SCALED_MAX_HEIGHT}    / $ratio);

#  ($page->{GALLERY_THUMB_MAX_WIDTH}, $page->{GALLERY_THUMB_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_THUMB_GEOMETRY} =~ /(\d*)[xX](\d*)/);
#  ($page->{GALLERY_MINITHUMB_MAX_WIDTH}, $page->{GALLERY_MINITHUMB_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_MINITHUMB_GEOMETRY} =~ /(\d*)[xX](\d*)/);
#  ($page->{GALLERY_SCALED_MAX_WIDTH}, $page->{GALLERY_SCALED_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_SCALED_GEOMETRY} =~ /(\d*)[xX](\d*)/);

  # create thumbs
  mkpath($target_dirname);
  ($page->{GALLERY_THUMB_WIDTH},     $page->{GALLERY_THUMB_HEIGHT})     = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_THUMB_TARGET_FILE},     $page->{GALLERY_THUMB_MAX_WIDTH}     . 'x' . $page->{GALLERY_THUMB_MAX_HEIGHT},     $page->{GALLERY_CONVERT_OPTIONS});
  ($page->{GALLERY_MINITHUMB_WIDTH}, $page->{GALLERY_MINITHUMB_HEIGHT}) = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_MINITHUMB_TARGET_FILE}, $page->{GALLERY_MINITHUMB_MAX_WIDTH} . 'x' . $page->{GALLERY_MINITHUMB_MAX_HEIGHT}, $page->{GALLERY_CONVERT_OPTIONS});
  ($page->{GALLERY_SCALED_WIDTH},    $page->{GALLERY_SCALED_HEIGHT})    = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_SCALED_TARGET_FILE},                                           'x' . $page->{GALLERY_SCALED_MAX_HEIGHT},    $page->{GALLERY_CONVERT_OPTIONS});

  # make sure the directory node holds MAX_WIDTH values
#  set_dir_dimensions($page, $page->{DIR});
}

#sub set_dir_dimensions
#{
#  my $page = shift;
#  my $dir = shift;
#  $dir->{GALLERY_THUMB_MAX_WIDTH}     = $page->{GALLERY_THUMB_WIDTH}     if((not exists($dir->{GALLERY_THUMB_MAX_WIDTH}))     || ($dir->{GALLERY_THUMB_MAX_WIDTH}     < $page->{GALLERY_THUMB_WIDTH}));
#  $dir->{GALLERY_MINITHUMB_MAX_WIDTH} = $page->{GALLERY_MINITHUMB_WIDTH} if((not exists($dir->{GALLERY_MINITHUMB_MAX_WIDTH})) || ($dir->{GALLERY_MINITHUMB_MAX_WIDTH} < $page->{GALLERY_MINITHUMB_WIDTH}));
##  $dir->{GALLERY_SCALED_MAX_WIDTH}    = $page->{GALLERY_SCALED_WIDTH}    if((not exists($dir->{GALLERY_SCALED_MAX_WIDTH}))    || ($dir->{GALLERY_SCALED_MAX_WIDTH}    < $page->{GALLERY_SCALED_WIDTH}));
#
#  set_dir_dimensions($page, $dir->{PARENT_DIR}) if($dir->{PARENT_DIR});
#}

sub dir_hook
{
  my $class = shift;
  my $dir = shift;

  # set defaults
  unless($dir->{GALLERY_TITLE})
  {
    my $title_match = $dir->{GALLERY_DEFAULT_DIR_TITLE};
    my $title = $dir->{NAME};
    if($title_match)
    {
      if($title =~ /$title_match/) {
        $title = $1;
        die "Bad match expression: $title_match" unless $title;
      }
    }
    if($dir->{GALLERY_TITLE_MATCH} && $dir->{GALLERY_TITLE_REPLACE}) {
      $title =~ s/$dir->{GALLERY_TITLE_MATCH}/$dir->{GALLERY_TITLE_REPLACE}/g;
    }
    $title =~ s/_/ /g;
    DEBUG "Setting gallery title: $title";
    $dir->{GALLERY_TITLE} = $title;
  }

  unless($dir->{GALLERY_DATE})
  {
    my $date_match = $dir->{GALLERY_DEFAULT_DATE};
    if($date_match)
    {
      my $date = $dir->{NAME};
      if($date =~ /$date_match/) {
        $date = $1;
        die "Bad match expression: $date_match" unless $date;
        DEBUG "Setting gallery date: $date";
        $dir->{GALLERY_DATE} = $date;
      }
    }
  }
}


sub gallery_resize_image
{
  my $infile = shift;
  my $outfile = shift;
  my $geometry = shift;
  my $options = shift || "";

  die unless($infile && $outfile && $geometry);

  if(-e $outfile) {
    DEBUG "Skipping image resize: $outfile";
  }
  else {
    INFO "Generating image resize: $outfile";
    my $cmd = "convert $options -scale $geometry \"$infile\" \"$outfile\"";
    `$cmd`;
  }
  return imgsize($outfile) ;
}

1;
