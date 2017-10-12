=head1 NAME

FileWiki::Plugin - Base class for all FileWiki plugins

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


package FileWiki::Plugin;

use strict;
use warnings;

use FileWiki;
use FileWiki::Logger;


our $VERSION = "0.50";

# returns true if the plugin is to be enabled for a given page
sub enabled
{
  my $class = shift;
  my $page = shift;
  my $plugin_name = shift;
  my $group = shift;
  my $plugin_match_key = "PLUGIN_" . uc($plugin_name) . "_MATCH";

  if($group) {
    my $enable = 0;
    foreach my $g (split(/\s*,\s*/, $group)) {
      # check PLUGIN_<GROUP>_MATCH
      my $group_match_key = "PLUGIN_GROUP_" . uc($g) . "_MATCH";
      if(not $page->{$group_match_key}) {
        WARN "Plugin group \"$g\" is enabled, but variable $group_match_key is not set.";
      }
      elsif($page->{SRC_FILE} =~ m/$page->{$group_match_key}/) {
        TRACE "Got group match on $group_match_key";
        return 1;
      }
      else {
        TRACE "No group match on $group_match_key";
      }
    }
    TRACE "No group match for $group, disabling plugin";
    return 0;
  }
  elsif($page->{$plugin_match_key}) {
    # check PLUGIN_<PLUGIN>_MATCH
    if($page->{SRC_FILE} =~ m/$page->{$plugin_match_key}/) {
      TRACE "Got match on $plugin_match_key";
      return 1;
    }
    else {
      TRACE "No match on $plugin_match_key, disabling plugin";
      return 0;
    }
  }
  else {
    # check MATCH_DEFAULT module variable
    no strict 'refs';
    my $match = ${$class . '::MATCH_DEFAULT'};
    unless($match) {
      WARN "Plugin \"$plugin_name\" is enabled, but variable $plugin_match_key is not set.";
      return 0;
    }
    unless($page->{SRC_FILE} =~ m/$match/) {
      TRACE "No match on \"\$${class}::MATCH_DEFAULT\", disabling plugin";
      return 0;
    }
    return 1;
  }
  return 0;
}

sub process_page
{
  my $self = shift;
  my $page = shift;
  my $filewiki = shift;
  my $data = "";

  return unless($page->{SRC_FILE});

  # process the filter chain
  DEBUG "Processing filter chain: $self->{name}"; INDENT 1;
  foreach my $filter_function (@{$self->{filter}})
  {
    $data = &$filter_function($data, $page, $filewiki);
    TRACE "Data length=" . length($data);
  }
  INDENT -1;

  return $data;
}


# called by FileWiki for determining the target file name
sub get_uri_filename
{
  my $self = shift;
  my $page = shift;
  my $name = $page->{NAME} || die("No NAME specified");
  my $target_file_ext = $self->{target_file_ext} || die("No target_file_ext specified: $self");

  return $name . '.' . $target_file_ext;
}

# called by FileWiki if plugin->{vars_provider} is set
sub update_vars
{
  my $self = shift;
  my $page = shift;

  ERROR "Plugin $self->{name} identifies itself as vars_provider, but does not implement the update_vars() method!";
}

# called by resource_creator plugins
sub add_resource
{
  my $self = shift;
  my $page = shift;
  my $key = shift;
  my $value = shift;
  die unless((ref($value) eq 'HASH') && $value->{TARGET_FILE});

  $page->{RESOURCE} //= {};
  WARN "Duplicate resource \"$key\"" if(exists($page->{RESOURCE}->{$key}));
  DEBUG "Adding page resource: $key";

  $value->{PLUGIN_NAME} = $self->{name};
  $page->{RESOURCE}->{$key} = $value;
}

# called by resource_creator plugins
sub resource_needs_rebuild
{
  my $self = shift;
  my $page = shift;
  my $target_file = shift;
  die unless($target_file);
  if($page->{RESOURCES_FORCE_REBUILD}) {
    DEBUG "Force rebuild of resource (RESOURCES_FORCE_REBUILD is set): $target_file";
    return 1;
  }

  my $target_mtime = (stat $target_file)[9];
  unless(defined($target_mtime)) {
    DEBUG "Resource target does not exist, needs rebuild: $target_file";
    return 1;
  }

  if($page->{TARGET_MTIME}) {
    my $check_mtime = FileWiki::unix_time($page->{TARGET_MTIME});
    unless(defined($check_mtime)) {
      WARN "Error parsing TARGET_MTIME=\"$page->{TARGET_MTIME}\", forcing resource rebuild: $target_file";
      return 1;
    }
    if($check_mtime <= $target_mtime) {
      DEBUG "Resource target exists and is not older than TARGET_MTIME, skipping rebuild: $target_file";
      return 0;
    }
    else {
      DEBUG "Resource target exists and is older than TARGET_MTIME, needs rebuild: $target_file";
      return 1;
    }
  }
  if($page->{SRC_FILE_MTIME} <= $target_mtime) {
    DEBUG "Resource target exists and is not older than source, skipping rebuild: $target_file";
    return 0;
  }
  else {
    DEBUG "Resource target exists and is older than source, needs rebuild: $target_file";
    return 1;
  }
  die;
}

1;
