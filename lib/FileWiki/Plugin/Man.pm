=head1 NAME

FileWiki::Plugin::Man - man page plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Man
    PLUGIN_MAN_MATCH=\.[1-8]$

=head1 DESCRIPTION

- Transforms the source using man2html.

- Applies the template specified by the TEMPLATE variable to the
  unmodified source file text.

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2015 Axel Burri. All rights reserved.

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

our $VERSION = "0.40";

my $match_default = '\.[1-8]$';

sub new
{
  my $class = shift;
  my $page = shift;
  my $match = $page->{uc("PLUGIN_MAN_MATCH")} || $match_default;

  return undef if($page->{IS_DIR});
  return undef unless($page->{SRC_FILE} =~ m/$match/);

  my $self = {
    name => $class,
    page_handler     => 1,
    vars_provider    => 1,
    target_file_ext  => 'html',
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

  $page->{MAN_NAME} = $page->{NAME};
  if($page->{SRC_FILE} =~ /\.([1-8])$/) {
    DEBUG "Setting variable MAN_SECTION=$1";
    $page->{MAN_SECTION} = $1;
    $page->{MAN_NAME} .= "($1)";
  }
  else {
    WARN "Failed to determine MAN_SECTION, setting to 0";
    $page->{MAN_SECTION} = 0;
  }
}


sub convert_source
{
  my $in = shift;
  my $page = shift;
  my $sfile = $page->{SRC_FILE};

  # man2html always returns with exitcode 0
  my $html = `/usr/bin/man2html -p -r $sfile`;
  chomp($html);

  # very hacky, but man2html is not flexible at all...
  # this will probably break in future versions of man2html...
  $html =~ s/^.*?Return to Main Contents<\/A><HR>\n\n//ms;
  $html =~ s/<P>\n\n<HR>\n<A NAME="index">.*$//ms;

  # change H2 into H1
  $html =~ s/<H2/<H1/gms;
  $html =~ s/<\/H2>/<\/H1>/gms;

  # remove links to other man pages
  $html =~ s/<A HREF="\.\.\/man.*?\>(.*?)<\/A>/$1/gms;

  # remove index anchors
  $html =~ s/<A NAME="[a-zA-Z]+">&nbsp;<\/A>\n//gms;
  return $html;
}


1;
