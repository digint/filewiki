=head1 NAME

FileWiki::Plugin - Base class for all FileWiki plugins

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2014 Axel Burri. All rights reserved.

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

use FileWiki::Logger;


our $VERSION = "0.40";

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

1;
