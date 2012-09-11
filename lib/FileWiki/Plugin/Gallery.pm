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


our $VERSION = "0.10";

my $match_default = '\.(jpg|JPG|jpeg|JPEG)$';

sub new
{
  my $class = shift;
  my $file = shift;
  my $type = shift;
  my $match = shift || $match_default;

  return undef unless($type eq "file");
  return undef unless($file =~ m/$match/);

  my $self = {
    name => $class,
    target_type => 'html',
    filter => [
      \&gallery_create_thumb,
      \&gallery_create_minithumb,
      \&gallery_create_scaled,
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub gallery_resize_image
{
  my $infile = shift;
  my $outfile = shift;
  my $geometry = shift;

  die unless($infile && $outfile && $geometry);

  if(-e $outfile) {
    INFO "Skipping image resize: $outfile";
  }
  else {
    INFO "Generating image resize: $outfile";
    my $cmd = "convert -scale $geometry \"$infile\" \"$outfile\"";
    `$cmd`;
  }
}

sub gallery_create_thumb
{
  my $self = shift;
  my $in = shift;
  my $page = shift;
  gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_THUMB_TARGET_FILE}, $page->{GALLERY_THUMB_SIZE});
  return $in;
}

sub gallery_create_minithumb
{
  my $self = shift;
  my $in = shift;
  my $page = shift;
  gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_MINITHUMB_TARGET_FILE}, $page->{GALLERY_MINITHUMB_SIZE});
  return $in;
}

sub gallery_create_scaled
{
  my $self = shift;
  my $in = shift;
  my $page = shift;
  gallery_resize_image($page->{SRC_FILE}, $page->{GALLERY_SCALED_TARGET_FILE}, $page->{GALLERY_SCALED_SIZE});
  return $in;
}

sub set_page_vars
{
  my $self = shift;
  my $page = shift;

  my $thumb_name = $page->{NAME} . '_thumb.jpg';
  my $minithumb_name = $page->{NAME} . '_minithumb.jpg';
  my $scaled_name = $page->{NAME} . '_scaled.jpg';
  my (undef, $target_dirname, undef) = splitpath($page->{TARGET_FILE});
  my (undef, $uri_dirname, undef) = splitpath($page->{URI});

  $page->{GALLERY_THUMB_TARGET_FILE} = $target_dirname . $thumb_name;
  $page->{GALLERY_THUMB_URI} = $uri_dirname . $thumb_name;
  $page->{GALLERY_MINITHUMB_TARGET_FILE} = $target_dirname . $minithumb_name;
  $page->{GALLERY_MINITHUMB_URI} = $uri_dirname . $minithumb_name;
  $page->{GALLERY_SCALED_TARGET_FILE} = $target_dirname . $scaled_name;
  $page->{GALLERY_SCALED_URI} = $uri_dirname . $scaled_name;

  my $gallery_src_file = $page->{SRC_FILE};
  $gallery_src_file =~ s/^$page->{BASEDIR}/$page->{GALLERY_ORIGINAL_URI_PREFIX}/;
  $page->{GALLERY_SRC_FILE} = $gallery_src_file;
}

1;
