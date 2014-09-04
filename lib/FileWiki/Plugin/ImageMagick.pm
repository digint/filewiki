# see: http://www.imagemagick.org/script/perl-magick.php

package FileWiki::Plugin::ImageMagick;

use strict;
use warnings;

use FileWiki::Logger;
use FileWiki::Filter;
use FileWiki::Plugin;

use Image::ExifTool;
use Image::Size qw(imgsize);
use Image::Magick;
use File::Path qw(mkpath);

use base qw( FileWiki::Plugin );


our $VERSION = "0.50";

my $match_default  = '\.(bmp|gif|jpeg|jpeg2000|mng|png|psd|raw|svg|tif|tiff|gif|jpeg|jpg|png|pdf|BMP|GIF|JPEG|JPEG2000|MNG|PNG|PSD|RAW|SVG|TIF|TIFF|GIF|JPEG|JPG|PNG|PDF)$';
my $format_default = 'jpg';

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
  my $page = shift;
  my $key = shift;
  my $mime_type = shift;
  my $shared_image = shift;

  # determine target file name
  $key = uc($key);
  my $format = $page->{"IMAGEMAGICK_FORMAT_$key"} || $page->{IMAGEMAGICK_FORMAT} || $format_default;
  $format = uc($format);
  my $name = $page->{NAME} . "_" . lc($key) . '.' . lc($format);
  my $target_dir = $page->{TARGET_DIR};
  my $target_file = $target_dir . $name;
  my $src_file = $page->{SRC_FILE};

  die unless($key && $format && $target_dir && $src_file);

  # don't create already existing images
  # FIXME: consider checking file date against src_file and VARS_FILES
  my ($width, $height);
  if (-e $target_file) {
    DEBUG "Resource target file exists: $target_file";
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
    im_assert($image->Strip()) if(defined($page->{"IMAGEMAGICK_STRIP_$key"}) ? $page->{"IMAGEMAGICK_STRIP_$key"} : $page->{"IMAGEMAGICK_STRIP"});

    # use this to stretch the image
    #$x = $image->Scale(height => "720");
    my $geometry = $page->{"IMAGEMAGICK_SCALE_$key"} || $page->{"IMAGEMAGICK_SCALE"};
    im_assert($image->Scale(geometry => $geometry)) if($geometry);

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

  my @resources = split(/\s*,\s*/, $page->{IMAGEMAGICK_RESOURCES});
  foreach my $resource (@resources) {
    DEBUG "Processing ImageMagick resource: $resource"; INDENT 1;

    my $key;
    my $mime_type;
    if($resource =~ /^([A-Z][A-Z0-9_]*):\s*([-\w\+]+\/[-\w\+]+)$/) {
      ($key, $mime_type) = ($1, $2);
    }
    elsif($resource =~ /^[A-Z][A-Z0-9_]*$/) {
      ($key, $mime_type) = ($1, undef);
    }
    else {
      ERROR "Invalid IMAGEMAGICK_RESOURCES declaration: expected \"<resource>[:<mime_type>]\", got \"$resource\"";
      next;
    }

    (my $ret, $shared_image) = create_image_resource($page, $key, $mime_type, $shared_image);
    WARN "ImageMagick target failed, skipping resource" unless($ret);
    $self->add_resource($page, $key, $ret) if($ret);
    INDENT -1;
  };
}



sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{PLUGIN_IMAGEMAGICK_MATCH} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name             => $class,
    page_handler     => 0,
    vars_provider    => 0,
    resource_creator => 1,
  };

  bless $self, ref($class) || $class;
  return $self;
}

1;
