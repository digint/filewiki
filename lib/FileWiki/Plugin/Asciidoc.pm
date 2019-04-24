=head1 NAME

FileWiki::Plugin::Asciidoc - asciidoc page plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Asciidoc
    PLUGIN_ASCIIDOC_MATCH=\.asciidoc$

=head1 DESCRIPTION

- Transforms the source using "asciidoc" <http://asciidoc.org>

- Sets MAN_SECTION and MAN_NAME if the source is a man page

- Applies the template specified by the TEMPLATE variable to the
  unmodified source file text.

=head1 CONFIGURATION VARIABLES

=head2 ASCIIDOC_STYLESHEET

Sets PLUGIN_STYLESHEET (path to css file)

=head1 VARIABLE PRESETS

=head2 MAN_NAME

The name of the man page, e.g. "name(1)" (extracted from file name).

=head2 MAN_SECTION

The section (1..8) of the man page (extracted from file name).

=head2 MAN_SOURCE

Extracted from source content ":man source: xxx".

=head2 MAN_REVISION

Extracted from source content ":revision: xxx".

=head2 MAN_DATE

Extracted from source content ":date: xxx".

=head2 PLUGIN_STYLESHEET

Copied from value of $ASCIIDOC_STYLESHEET.

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


package FileWiki::Plugin::Asciidoc;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

our $VERSION = "0.51";

our $MATCH_DEFAULT = '\.(asciidoc|adoc)$';

sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    page_handler     => 1,
    vars_provider    => 1,
    target_file_ext  => 'html',
    filter => [
      \&FileWiki::Filter::read_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&convert_source,
      \&FileWiki::Filter::sanitize_newlines,
      \&FileWiki::Filter::apply_template,
     ],
  };

  bless $self, ref($class) || $class;
  return $self;
}


sub update_vars
{
  my $self = shift;
  my $page = shift;
  $page->{PLUGIN_STYLESHEET} = $page->{ASCIIDOC_STYLESHEET} if($page->{ASCIIDOC_STYLESHEET});

  # similar to FileWikiPlugin::Man::update_vars, but no need to fix NAME
  my $name = $page->{NAME};
  if($name =~ s/\.([1-8])$//) {
    my $man_section = $1 ;
    DEBUG "Setting variable MAN_SECTION=$1";
    $page->{MAN_SECTION} = $man_section;
    $page->{MAN_NAME} = "$name($man_section)";
    $page->{MAN_MANNAME} = "$name";
  }
}


sub convert_source
{
  my $in = shift;
  my $page = shift;

  # parse mandoc
  if($in =~ /^:date:\s*([0-9-]+)/ms) {
    $page->{MAN_DATE} = $1;
    DEBUG "Setting variable MAN_DATE=$1";
  }
  if($in =~ /^:revision:\s*([0-9a-zA-Z-.]+)/ms) {
    $page->{MAN_REVISION} = $1;
    DEBUG "Setting variable MAN_REVISION=$1";
  }
  if($in =~ /^:man source:\s*([0-9a-zA-Z-.]+)/ms) {
    $page->{MAN_SOURCE} = $1;
    DEBUG "Setting variable MAN_SOURCE=$1";
  }

  # NOTE: asciidoc command will read from file, NOT $in !

  my $sfile = $page->{SRC_FILE};
  my $asciidoc_backend = $page->{ASCIIDOC_BACKEND} // "html";
  my $asciidoc_doctype = $page->{ASCIIDOC_DOCTYPE} // "article";
  my $cmd = "/usr/bin/asciidoc --backend $asciidoc_backend --doctype $asciidoc_doctype --no-header-footer -o - $sfile";
  DEBUG "Converting asciidoc: $cmd";

  # build header
  my $html = '<div class="fw-asciidoc">';
  if($page->{MAN_SOURCE}) {
    $html .= '<div id="fw-asciidoc-header">';
    $html .= "<h1>$page->{MAN_MANNAME} Man Page</h1>";
    $html .= "<span>$page->{MAN_NAME},</span>";
    $html .= '<span id="revnumber">version ' . $page->{MAN_REVISION} . ',</span>' if($page->{MAN_REVISION});
    $html .= '<span id="revdate">' . $page->{MAN_DATE} . '</span>' if($page->{MAN_DATE});
    $html .= '</div>'; # id="fw-asciidoc-header"
  }
  $html .= '<div id="fw-asciidoc-content">';

  $html .= `$cmd`;
  $html .= '</div>'; # id="fw-asciidoc-content
  $html .= '</div>'; # class="fw-asciidoc"

  return $html;
}


1;
