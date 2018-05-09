=head1 NAME

FileWiki::Plugin::Markdown - Markdown plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=HTML
    PLUGIN_MARKDOWN_MATCH=\.txt$

=head1 DESCRIPTION

- Honors nested vars.

- Strips the nested vars from the source.

- Transforms the source using the Markdown markup language (See
  Text::Markdown and <http://daringfireball.net/projects/markdown/>
  for details).

- Applies the template specified by the TEMPLATE variable to the
  transformed text.

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


package FileWiki::Plugin::Markdown;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

use Text::Markdown;

our $VERSION = "0.50";

our $MATCH_DEFAULT = '\.(md|txt)$';


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    page_handler     => 1,
    read_nested_vars => 1,
    target_file_ext  => 'html',
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&FileWiki::Filter::strip_nested_vars,
      \&FileWiki::Filter::strip_xml_comments,
      \&transform_markdown,
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub transform_markdown
{
  my $in = shift;
  my $page = shift;
  my $filewiki = shift;

  my $r = $filewiki->refs();

  # make a copy of the references, with lowercase keys (Text::Markdown accepts only lowercase refs for some reason)
  # note: Text::Markdown modifies the urls hash!
  my %refs;
  @refs{ map { lc($_) } keys %$r } = values %$r;

  DEBUG "Converting Markdown";

  return Text::Markdown::markdown($in, { urls => \%refs });
}

1;
