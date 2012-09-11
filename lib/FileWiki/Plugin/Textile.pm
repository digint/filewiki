=head1 NAME

FileWiki::Plugin::Textile - Textile plugin for FileWiki

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


package FileWiki::Plugin::Textile;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

use Text::Textile;

our $VERSION = "0.10";

my $match_default = '\.(textile)$';

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
    nested_vars => 1,
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&FileWiki::Filter::strip_nested_vars,
      \&FileWiki::Filter::strip_xml_comments,
      \&transform_textile,
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub transform_textile
{
  my $filewiki = shift;
  my $in = shift;
  DEBUG "Converting Textile";

  my $refs = $filewiki->refs();
  my $ti = Text::Textile::DefaultLinks->new();
  # set the link references for Textile
  $ti->{default_links}{$_} = { url => $refs->{$_}, title => undef } foreach (keys %$refs);
  return $ti->process($in);
}

1;
