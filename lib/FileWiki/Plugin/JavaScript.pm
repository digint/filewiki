=head1 NAME

FileWiki::Plugin::JavaScript - JavaScript plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=JavaScript
    PLUGIN_JAVASCRIPT_MATCH=(?<!\.min)\.js$

=head1 DESCRIPTION

- Honors nested vars.

- Strips the nested vars from the source (for ".jstt" files, or forced
  if "process_template" argument is set).

- Transforms the source using TemplateToolkit (for ".jstt" files, or
  forced if "process_template" argument is set).

- Minifies the JavaScript using JavaScript::Minifier

=head1 PLUGIN ARGUMENTS

- disable_minify: skip minify

- process_template: if set, run TemplateToolkit on source

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


package FileWiki::Plugin::JavaScript;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

our $VERSION = "0.53";

our $MATCH_DEFAULT = '\.(js|jstt)$';


sub new
{
  my $class = shift;
  my $page = shift;
  my @args = split(/,\s*/, shift);
  my $disable_minify   = grep "disable_minify", @args;
  my $process_template = grep "process_template", @args;
  $process_template = 1 if($page->{SRC_FILE} =~ /\.jstt$/);

  my $self = {
    name => $class,
    page_handler     => 1,
    read_nested_vars => 1,
    target_file_ext  => 'js',
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      $process_template ? \&FileWiki::Filter::strip_nested_vars : (),
      $process_template ? \&FileWiki::Filter::process_template : (),
      $disable_minify ? () : \&minify_javascript,
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
