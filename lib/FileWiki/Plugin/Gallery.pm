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

use File::Spec::Functions qw(splitpath);
use Image::ExifTool;
use Image::Size qw(imgsize);
use File::Path qw(mkpath);

our $VERSION = "0.20";

my $match_default = '\.(jpg|JPG|jpeg|JPEG)$';

# TODO: orientation, subject distance, use these
my @exif_tags = qw( Make
                    Model
                    ColorSpaceData
                    Flash
                    ShutterSpeedValue
                    DateCreated
                 );

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
  # TODO: target stuff goes to self
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
  # TODO: rename->URI
  my $gallery_src_file = $page->{SRC_FILE};
  $gallery_src_file =~ s/^$page->{BASEDIR}/$page->{GALLERY_ORIGINAL_URI_PREFIX}/;
  $page->{GALLERY_SRC_FILE} = $gallery_src_file;

  # set defaults
  $page->{GALLERY_TITLE} = $page->{NAME} unless($page->{GALLERY_TITLE});

  # fetch exif data
  my $exif = Image::ExifTool->new();
  $exif->Options(Unknown => 1) ;
  $exif->Options(DateFormat => "%Y-%m-%d %H:%M:%S"); # TODO

  my $infos = $exif->ImageInfo($page->{SRC_FILE});
  my @final;
  foreach (keys(%$infos)) {
    push @final, [ $_, $exif->GetDescription($_), $infos->{$_} ];
  }

  $page->{GALLERY_EXIF} = \@final;
  $page->{GALLERY_SRC_WIDTH} = $infos->{ImageWidth};
  $page->{GALLERY_SRC_HEIGHT} = $infos->{ImageHeight};
  ($page->{GALLERY_DATE}, $page->{GALLERY_TIME}) = ($1, $2) if($infos->{DateTimeOriginal} =~ m/(\S*)\s*(\S*)/);

  # create thumbs
  mkpath($target_dirname);
  ($page->{GALLERY_THUMB_WIDTH},     $page->{GALLERY_THUMB_HEIGHT})     = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_THUMB_TARGET_FILE},     'x' . $page->{GALLERY_THUMB_MAX_HEIGHT},     $page->{GALLERY_CONVERT_OPTIONS});
  ($page->{GALLERY_MINITHUMB_WIDTH}, $page->{GALLERY_MINITHUMB_HEIGHT}) = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_MINITHUMB_TARGET_FILE}, 'x' . $page->{GALLERY_MINITHUMB_MAX_HEIGHT}, $page->{GALLERY_CONVERT_OPTIONS});
  ($page->{GALLERY_SCALED_WIDTH},    $page->{GALLERY_SCALED_HEIGHT})    = gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_SCALED_TARGET_FILE},    'x' . $page->{GALLERY_SCALED_MAX_HEIGHT},    $page->{GALLERY_CONVERT_OPTIONS});

  # make sure the directory node holds MAX_WIDTH values
  $page->{DIR}->{GALLERY_THUMB_MAX_WIDTH}     = $page->{GALLERY_THUMB_WIDTH}     if((not exists($page->{DIR}->{GALLERY_THUMB_MAX_WIDTH}))     || ($page->{DIR}->{GALLERY_THUMB_MAX_WIDTH}     < $page->{GALLERY_THUMB_WIDTH}));
  $page->{DIR}->{GALLERY_MINITHUMB_MAX_WIDTH} = $page->{GALLERY_MINITHUMB_WIDTH} if((not exists($page->{DIR}->{GALLERY_MINITHUMB_MAX_WIDTH})) || ($page->{DIR}->{GALLERY_MINITHUMB_MAX_WIDTH} < $page->{GALLERY_MINITHUMB_WIDTH}));
  $page->{DIR}->{GALLERY_SCALED_MAX_WIDTH}    = $page->{GALLERY_SCALED_WIDTH}    if((not exists($page->{DIR}->{GALLERY_SCALED_MAX_WIDTH}))    || ($page->{DIR}->{GALLERY_SCALED_MAX_WIDTH}    < $page->{GALLERY_SCALED_WIDTH}));

#  # TODO: define like this in tree.vars
#  ($page->{GALLERY_THUMB_MAX_WIDTH}, $page->{GALLERY_THUMB_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_THUMB_SIZE} =~ /(\d+)[xX](\d+)/);
#  ($page->{GALLERY_MINITHUMB_MAX_WIDTH}, $page->{GALLERY_MINITHUMB_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_MINITHUMB_SIZE} =~ /(\d+)[xX](\d+)/);
#  ($page->{GALLERY_SCALED_MAX_WIDTH}, $page->{GALLERY_SCALED_MAX_HEIGHT}) = ($1, $2) if($page->{GALLERY_SCALED_SIZE} =~ /(\d+)[xX](\d+)/);

}

sub dir_hook
{
  my $class = shift;
  my $dir = shift;
  my $date_match = $dir->{GALLERY_DEFAULT_DATE};
  my $title_match = $dir->{GALLERY_DEFAULT_TITLE};

  my $title = $dir->{NAME};
  if($title_match)
  {
    if($title =~ /$title_match/) {
      $title = $1;
      die "Bad match expression: $title_match" unless $title;
    }
  }
  DEBUG "Setting gallery title: $title";
  $dir->{GALLERY_TITLE} = $title;

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

# sub gallery_create_thumb
# {
#   my $self = shift;
#   my $in = shift;
#   my $page = shift;
#   gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_THUMB_TARGET_FILE}, 'x' . $page->{GALLERY_THUMB_MAX_HEIGHT});
#   return $in;
# }

# sub gallery_create_minithumb
# {
#   my $self = shift;
#   my $in = shift;
#   my $page = shift;
#   gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_MINITHUMB_TARGET_FILE}, 'x' . $page->{GALLERY_MINITHUMB_MAX_HEIGHT});
#   return $in;
# }

# sub gallery_create_scaled
# {
#   my $self = shift;
#   my $in = shift;
#   my $page = shift;
#   gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_SCALED_TARGET_FILE}, 'x' . $page->{GALLERY_SCALED_MAX_HEIGHT});
#   return $in;
# }

1;
