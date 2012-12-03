=head1 NAME

FileWiki::Plugin::JavaScript - JavaScript plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=JavaScript
    PLUGIN_JAVASCRIPT_MATCH=(?<!\.min)\.js$

=head1 DESCRIPTION

- Transforms the source using TemplateToolkit.

- Minifies the JavaScript using JavaScript::Minifier

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012 Axel Burri. All rights reserved.

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


package FileWiki::Plugin::JavaScript;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

our $VERSION = "0.30";

my $match_default = '\.js$';

sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{uc("PLUGIN_JavaScript_MATCH")} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name => $class,
    target_file_ext => 'js',
    read_nested_vars => 1,
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
#      \&FileWiki::Filter::strip_nested_vars,
#      \&FileWiki::Filter::process_template,
      \&minify_javascript,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub minify_javascript
{
  my $in = shift;

  if(eval "require JavaScript::Minifier;") {
    DEBUG "Minifying JavaScript";
    return JavaScript::Minifier::minify(input => $in);
  }

  WARN "Perl module JavaScript::Minifier not found, skipping JavaScript minify";
  return $in;
}


1;
