=head1 NAME

FileWiki::Plugin::Man - man page plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Man
    PLUGIN_MAN_MATCH=\.[1-8]$

=head1 DESCRIPTION

- Transforms the source using man2html.

- Applies the template specified by the TEMPLATE variable to the
  unmodified source file text.

=head1 CONFIGURATION VARIABLES

=head2 MAN_CONVERT

Specify conversion tool. Supported values: "groff" or "man2html",
defaults to "groff".

=head1 VARIABLE PRESETS

=head2 NAME

Sets the NAME back to "name.1" (push file extension back to NAME).

=head2 MAN_NAME

The name of the man page, e.g. "name(1)" (extracted from file name).

=head2 MAN_SECTION

The section (1..8) of the man page (extracted from file name).

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


package FileWiki::Plugin::Man;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use FileWiki::Filter;

our $VERSION = "0.51";

our $MATCH_DEFAULT = '\.[1-8]$';

sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    page_handler     => 1,
    vars_provider    => 1,
    target_file_ext  => 'html', # NOTE: we override get_uri_filename() below!
    filter => [
      \&convert_source,
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

  my $man_section = 0;
  $man_section = $1 if($page->{SRC_FILE} =~ /\.([1-8])$/);
  DEBUG "Setting variable MAN_SECTION=$1";
  WARN "Failed to determine MAN_SECTION, setting to 0" unless($man_section);

  $page->{MAN_SECTION} = $man_section;
  $page->{MAN_NAME} = "$page->{NAME}($man_section)";

  # re-add man section in NAME, this was eaten up by FileWiki (remove file extension)
  $page->{NAME} .= '.' . $man_section;
}


# add MAN_SECTION to filename (this is eaten up from NAME by FileWiki)
sub get_uri_filename
{
  my $self = shift;
  my $page = shift;
  my $name = $page->{NAME} || die("No NAME specified");
  my $target_file_ext = $self->{target_file_ext} || die("No target_file_ext specified: $self");

  my $man_section = 0;
  $man_section = $1 if($page->{SRC_FILE} =~ /\.([1-8])$/);
  return "$name.$man_section.$target_file_ext";
}


sub convert_source
{
  my $in = shift;
  my $page = shift;
  my $sfile = $page->{SRC_FILE};
  my $convert_tool = $page->{MAN_CONVERT} // "groff";

  my $html;
  if($convert_tool eq "man2html")
  {
    # man2html always returns with exitcode 0
    $html = `/usr/bin/man2html -p -r $sfile`;
    chomp($html);

    # very hacky, but man2html is not flexible at all...
    # this will probably break in future versions of man2html...
    $html =~ s/^.*?Return to Main Contents<\/A><HR>\n\n//ms;
    $html =~ s/<P>\n\n<HR>\n<A NAME="index">.*$//ms;

    # remove links to other man pages
    $html =~ s/<A HREF="\.\.\/man.*?\>(.*?)<\/A>/$1/gms;

    # fix double quotes. in groff, use "\[lq]" instead of "\(lq"
    $html =~ s/\[lq\]/&ldquo;/gms;
    $html =~ s/\[rq\]/&rdquo;/gms;

    # remove index anchors
    $html =~ s/<A NAME="[a-zA-Z]+">&nbsp;<\/A>\n//gms;

    # change H2 into H1
    $html =~ s/<H2/<H1/gms;
    $html =~ s/<\/H2>/<\/H1>/gms;
  }
  else
  {
    # use "groff" for conversion
    my $cmd = "/usr/bin/groff -Txhtml -mandoc";
    $cmd .= " -P -l" unless($page->{MAN_ENABLE_SECTION_LINKS});
    $cmd .= " -P -r" unless($page->{MAN_ENABLE_HEADER_FOOTER_LINE});

    # add ".RE 0" line after each ".SH *" line
    $cmd = "/bin/cat $sfile | /bin/sed '" . '/^\.SH\s/ s/$/\n.RE 0/' . "' | " . $cmd;

    $html = `$cmd`;
    chomp($html);

    # extract body
    $html =~ s/^.*<body>/<div class="grohtml">/ms;
    $html =~ s/<\/body>.*/<\/div>/ms;

    # remove header
    $html =~ s/<h1>.*?<\/h1>//gms;

    # change H2 into H1
    $html =~ s/<h2/<h1/gms;
    $html =~ s/<\/h2>/<\/h1>/gms;
  }

  return $html;
}


1;
