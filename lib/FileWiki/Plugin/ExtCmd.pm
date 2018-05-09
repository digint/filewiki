=head1 NAME

FileWiki::Plugin::ExtCmd - Generate resources with external command

=head1 SYNOPSIS

    PLUGINS=ExtCmd(MP4)
    PLUGIN_EXTCMD_MATCH=\.(mp4|MP4|avi|AVI)$

    EXTCMD_TARGET_POSTFIX_MP4           .mp4
    EXTCMD_MIME_TYPE_MP4                video/mp4
    EXTCMD_MP4                          ffmpeg -y -i __INFILE__ -loglevel warning -copyts __OPTIONS__ __OUTFILE__
    EXTCMD_MP4_OPTION_SCALE             -vf scale=-1:360
    EXTCMD_MP4_OPTION_FORMAT            -f mp4
    EXTCMD_MP4_OPTION_VIDEO_CODEC       -codec:v libx264
    EXTCMD_MP4_OPTION_VIDEO_PROFILE     -profile:v baseline
    EXTCMD_MP4_OPTION_VIDEO_QUALITY     -crf 30 -preset slow
    EXTCMD_MP4_OPTION_AUDIO_CODEC       -codec:a aac -strict experimental
    EXTCMD_MP4_OPTION_AUDIO_BITRATE     -b:a 128k

=head1 DESCRIPTION

Generates resources by executing a user-defined command.

=head1 PLUGIN ARGUMENTS

List of resource keys. A separate command is executed for each
resource key, with the options from the configuration variables.

=head1 CONFIGURATION VARIABLES

=head2 EXTCMD_TARGET_POSTFIX, EXTCMD_TARGET_POSTFIX_<resource_key>

File suffix of the generated target file. If no <resource_key> is
provided, the given target postfix will be used as default for all
resources.

=head2 EXTCMD_MIME_TYPE, EXTCMD_MIME_TYPE_<resource_key>

Specify the mime type of the resource. If no <resource_key> is
provided, the given mime type will be used as default for all
resources.

=head2 EXTCMD_<resource_key>

Specifies commands to be executed for a resource key. Commands
expand the following placeholders:

 - __INFILE__   : Input file
 - __OUTFILE__  : Output file
 - __OPTIONS__  : Options specified by EXTCMD_<resource_key>_OPTION_<option_key>
                  variables (see below).

Example (create a scaled JPG file using imagemagick):

    EXTCMD_TARGET_POSTFIX_LOWRES        _lowres.jpg
    EXTCMD_MIME_TYPE_LOWRES             image/jpeg
    EXTCMD_LOWRES                       convert __OPTIONS__ __INFILE__ __OUTFILE__
    EXTCMD_LOWRES_OPTION_GEOMETRY       -scale '2560x1440>'
    EXTCMD_LOWRES_OPTION_ORIENT         -auto-orient
    EXTCMD_LOWRES_OPTION_QUALITY        -quality 75
    EXTCMD_LOWRES_OPTION_STRIP          -strip

=head2 EXTCMD_<resource_key>_OPTION_<option_key>

Specifies options to replace the __OPTIONS__ placeholder string of the
EXTCMD_<resource_key> variable. Using this variable is particulary
useful when you want to change only a specific option later in a .vars
file.

Example (in "my_important_image.jpg.vars", to continue example above)

    EXTCMD_LOWRES_OPTION_QUALITY        -quality 90

This will set the image quality for "my_important_image_lowres.jpg" to
a higher value as the other LOWRES resources.

=head1 VARIABLE PRESETS

For each resource, a new entry in the RESOURCE hash is generated:

    RESOURCE => {
      ...
      <resource_key> => {
        'NAME'        => <target name>,
        'URI'         => <target URI>,
        'MIME_TYPE'   => <target mime type>,
        'TARGET_FILE' => <target file>,
        'PLUGIN_NAME' => 'FileWiki::Plugin::ImageMagick',
      }
    }

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2018 Axel Burri. All rights reserved.

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


package FileWiki::Plugin::ExtCmd;

use strict;
use warnings;

use FileWiki::Logger;
use FileWiki::Plugin;

use File::Path qw(mkpath);

use base qw( FileWiki::Plugin );

our $VERSION = "0.50";

our $MATCH_DEFAULT = undef;


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my @targets = split(/,\s*/, $args);

  my $self = {
    name             => $class,
    page_handler     => 0,
    vars_provider    => 0,
    resource_creator => 1,

    resource_targets => \@targets,
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub process_resources
{
  my $self = shift;
  my $page = shift;
  my $src_file = $page->{SRC_FILE};
  my @filelist;

  foreach my $key (@{$self->{resource_targets}})
  {
    DEBUG "Processing ExtCmd resource: $key"; INDENT 1;

    $key = uc($key);
    my $mime_type = $page->{"EXTCMD_MIME_TYPE_$key"} || $page->{EXTCMD_MIME_TYPE};
    my $target_postfix = $page->{"EXTCMD_TARGET_POSTFIX_$key"} || $page->{EXTCMD_TARGET_POSTFIX};
    unless($target_postfix) {
      $target_postfix =  '.' . lc($key);
      WARN "No EXTCMD_TARGET_POSTFIX_$key specified, using \"$target_postfix\"";
    }
    my $name = $page->{NAME} . $target_postfix;
    my $target_dir = $page->{TARGET_DIR};
    my $target_file = $target_dir . $name;

    die unless($src_file && $name && $target_dir && $target_file);

    if($self->resource_needs_rebuild($page, $target_file))
    {
      DEBUG "Source file: $src_file";

      # assemble command
      my $cmd = $page->{"EXTCMD_${key}"};
      unless($cmd) {
        ERROR "Resource command failed: missing variable EXTCMD_${key}"; INDENT -1;
        next;
      }
      my $options = '';
      foreach (keys %$page) {
        next unless(/^EXTCMD_${key}_OPTION_[A-Z0-9_]+$/);
        $options .= ' ' . $page->{$_};
      }
      $cmd =~ s/__INFILE__/"$src_file"/g;
      $cmd =~ s/__OUTFILE__/"$target_file"/g;
      $cmd =~ s/__OPTIONS__/$options/g;

      # execute command
      INFO ">>> $target_file";
      TRACE "Executing: $cmd";
      mkpath($target_dir);
      `$cmd`;
      if($?) {
        ERROR "Command execution failed ($?): $cmd"; INDENT -1;
        next;
      }
    }
    else
    {
      INFO "--- $target_file";
    }

    $self->add_resource($page, $key, {
      NAME        => $name,
      URI         => FileWiki::get_uri($page, $name),
      MIME_TYPE   => $mime_type,
      TARGET_FILE => $target_file,
    });
    push @filelist , $target_file;

    INDENT -1;
  }
  return @filelist;
}


sub exec_logged
{
  my $cmd = shift;
  my $target_dir = shift;
  DEBUG "$cmd";
  mkpath($target_dir);

  `$cmd`;
  if($?) {
    ERROR "Command execution failed ($?): $cmd";
    return 1;
  }
  return 0;
}

1;
