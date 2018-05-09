=head1 NAME

FileWiki::Plugin::Copy - Copy plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Copy
    PLUGIN_COPY_MATCH=\.(ico|css|png)$

=head1 DESCRIPTION

Copies files matching "PLUGIN_COPY_MATCH".

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


package FileWiki::Plugin::Copy;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

use File::Spec::Functions qw(splitpath);

our $VERSION = "0.50";

our $MATCH_DEFAULT = undef; # no default (makes setting of PLUGIN_COPY_MATCH mandatory)


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    page_handler => 1,
    filter => [
      \&FileWiki::Filter::read_source,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub get_uri_filename
{
  my $self = shift;
  my $page = shift;
  my (undef, undef, $file) = splitpath($page->{SRC_FILE});

  return $file;
}

1;
