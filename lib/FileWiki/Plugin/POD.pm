=head1 NAME

FileWiki::Plugin::POD - POD plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=POD
    PLUGIN_POD_MATCH=\.(pm|pl|pod)$

=head1 DESCRIPTION

- Honors nested vars.

- Strips the nested vars from the source.

- Transforms the source using the POD markup language (the standard
  documentation language used for perl projects)

- Applies the template specified by the TEMPLATE variable to the
  transformed text.

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


package FileWiki::Plugin::POD;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;
use Pod::Simple::HTML;

our $VERSION = "0.20";

my $match_default = '\.(pod|pm|pl)$';

sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{uc("PLUGIN_POD_MATCH")} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name => $class,
    target_file_ext => 'html',
    read_nested_vars => 1,
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&transform_pod,
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub transform_pod
{
  my $filewiki = shift;
  my $in = shift;
  DEBUG "Converting POD";

  my $out = '';
  my $parser = Pod::Simple::HTML->new();

  $parser->output_string(\$out);
  $parser->parse_string_document($in);

  $out =~ s/.*\<\!-- start doc --\>//ms;
  $out =~ s/\<\!-- end doc --\>.*//ms;
  return $out;
}

1;
