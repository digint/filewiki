=head1 NAME

FileWiki::Plugin::CSS - CSS plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=CSS
    PLUGIN_CSS_MATCH=\.csstt$

=head1 DESCRIPTION

- Honors nested vars.

- Strips the nested vars from the source.

- Transforms the source using TemplateToolkit.

- Minifies the CSS using CSS::Minifier

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2019 Axel Burri. All rights reserved.

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


package FileWiki::Plugin::CSS;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

our $VERSION = "0.50";

our $MATCH_DEFAULT = '\.csstt$';


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    page_handler     => 1,
    read_nested_vars => 1,
    target_file_ext  => 'css',
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&FileWiki::Filter::strip_nested_vars,
      \&FileWiki::Filter::process_template,
      \&minify_css,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub minify_css
{
  my $in = shift;

  if(eval "require CSS::Minifier;") {
    DEBUG "Minifying CSS";
    return CSS::Minifier::minify(input => $in);
  }

  WARN "Perl module CSS::Minifier not found, skipping CSS minify";
  return $in;
}


1;
