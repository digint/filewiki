=head1 NAME

FileWiki::Plugin::EXIF - EXIF variable provider plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=EXIF

=head1 DESCRIPTION

Provides page variables from EXIF data extracted from source files,
using Image::ExifTool.

=head1 CONFIGURATION VARIABLES

=head2 EXIF_SIDECAR_POSTFIX

Load additional EXIF information from sidecar files. Several file
postfixes can be specified, separated by colon (":").

Example:

    EXIF_SIDECAR_POSTFIX  .xmp:.XMP

This will load EXIF information from "myfile.jpg.xmp" in addition to
the EXIF information in "myfile.jpg".

=head2 EXIF_TIME_FORMAT

Time format used for for printing date/time values in EXIF_INFO hash
and EXIF_TIME variable. Corresponds to the C library routines
"strftime" and "ctime". Defaults to TIME_FORMAT page variable, which
again defaults to "%C".

=head2 EXIF_DISABLE_WARNINGS

Disable warnings generated when EXIF data is missing (especially on
missing EXIF_TIME)

=head1 VARIABLE PRESETS

=head2 EXIF_INFO

Hash of all EXIF information provided by the source image. Refer to
the manual of Image::ExifTool for more informations about the EXIF
keys.

    EXIF_INFO={ exif_key => { desc  => "Key description",
                              value => "EXIF value"
                              print => "EXIF value, human readable",
                              raw   => "raw EXIF value"
                            }
                exif_key...
              }

=head2 EXIF_TIME

Date/Time extracted from EXIF "DateTimeOriginal" key, formatted using
EXIF_TIME_FORMAT.

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

=cut


package FileWiki::Plugin::EXIF;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use Image::ExifTool;

our $VERSION = "0.50";

our $MATCH_DEFAULT = '\.(bmp|gif|jpeg|jpeg2000|mng|png|psd|raw|svg|tif|tiff|gif|jpeg|jpg|png|pdf|mp4|avi|BMP|GIF|JPEG|JPEG2000|MNG|PNG|PSD|RAW|SVG|TIF|TIFF|GIF|JPEG|JPG|PNG|PDF|MP4|AVI)$';


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    vars_provider => 1,
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub update_vars
{
  my $self = shift;
  my $page = shift;

  # fetch exif data
  my %exif_hash;
  my $exif = Image::ExifTool->new();
  $exif->Options(Unknown => 1) ;
  $exif->Options(DateFormat => $page->{EXIF_TIME_FORMAT} || $page->{TIME_FORMAT} || undef);

  my @exif_files = ( $page->{SRC_FILE} );
  if($page->{EXIF_SIDECAR_POSTFIX}) {
    push(@exif_files, $page->{SRC_FILE} . $_) foreach (split(/:/, $page->{EXIF_SIDECAR_POSTFIX}));
  }
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
  $page->{EXIF_INFO} = \%exif_hash;

#  if(exists($exif_hash{Orientation}) && ($exif_hash{Orientation}->{value} >= 5) && ($exif_hash{Orientation}->{value} <= 8)) {
#    # flipped orientation, swap w/h
#    $page->{EXIF_ROTATED_WIDTH} = $exif_hash{ImageHeight}->{value};
#    $page->{EXIF_ROTATED_HEIGHT} = $exif_hash{ImageWidth}->{value};
#  }
#  else {
#    $page->{EXIF_ROTATED_WIDTH} = $exif_hash{ImageWidth}->{value};
#    $page->{EXIF_ROTATED_WIDTH} = $exif_hash{ImageHeight}->{value};
#  }

  # set date / time
  $page->{EXIF_TIME} = $exif_hash{DateTimeOriginal}->{print} if(exists $exif_hash{DateTimeOriginal});
  $page->{EXIF_TIME} ||= $exif_hash{CreateDate}->{print} if(exists $exif_hash{CreateDate});

  unless($page->{EXIF_TIME}) {
    WARN "Invalid EXIF_TIME (missing EXIF data): $page->{SRC_FILE}" unless($page->{EXIF_DISABLE_WARNINGS});

    # WARN "No EXIF \"DateTimeOriginal\" found, setting date/time from MTIME: $page->{SRC_FILE}";
    # $page->{EXIF_TIME} = $page->{EXIF_TIME} || time2str($page->{EXIF_TIME_FORMAT} || $page->{TIME_FORMAT} || $FileWiki::default_date_format, $page->{SRC_FILE_MTIME});
  }
}


1;
