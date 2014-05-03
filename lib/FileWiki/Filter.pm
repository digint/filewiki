=head1 NAME

FileWiki::Filter - Common text filter functions for FileWiki plugins

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2014 Axel Burri. All rights reserved.

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


package FileWiki::Filter;

use strict;
use warnings;

use FileWiki::Logger;
use Template;

our $VERSION = "0.40";


sub read_source
{
  my $in = shift;
  my $page = shift;

  if($page->{SRC_TEXT})
  {
    DEBUG "Got " . length($page->{SRC_TEXT}) . " bytes of dynamic data, ignoring input file.";
    return $page->{SRC_TEXT};
  }
  else
  {
    my $data;
    my $sfile = $page->{SRC_FILE};
    DEBUG "Reading file: $sfile";
    open(INFILE, "<$sfile") or die "Failed to open file \"$sfile\": $!";
    {
      local $/;   # slurp the file
      $data = <INFILE>;
    }
    close(INFILE);

    WARN "Overwriting " . length($in) . " bytes of data with page source" if($in);

    return $data;
  }
}


sub strip_nested_vars
{
  my $in = shift;
  DEBUG "Stripping page nested vars";
  $in =~ s/^.?[<\[]filewiki_vars[>\]].*?^.?[<\[]\/filewiki_vars[>\]]\n//ms;
  return $in;
}


sub strip_xml_comments
{
  my $in = shift;
  DEBUG "Stripping xml-style comments";
  $in =~ s/<!----.*?---->//sg;
  return $in;
}

sub sanitize_newlines
{
  my $in = shift;
  DEBUG "Sanitizing newlines";
  $in =~ s/\r\n/\n/g;
  return $in;
}


sub apply_template
{
  my $in = shift;
  my $page = shift;

  unless($page->{TEMPLATE}) {
    if(defined($page->{TEMPLATE})) {
      DEBUG "'TEMPLATE' variable disabled, skipping template processing: $page->{SRC_FILE}";
    }
    else {
      WARN "'TEMPLATE' variable not specified, skipping template processing: $page->{SRC_FILE}";
    }
    return $in;
  }

  $page->{TEMPLATE_INPUT} = $in;
  my $template = $page->{TEMPLATE};
  DEBUG "Processing template: $template"; INDENT 1;
  my $out = _process_template($template, $page);
  INDENT -1;

  return $out;
}


sub process_template
{
  my $in = shift;
  my $page = shift;

  DEBUG "Processing template text"; INDENT 1;
  my $out = FileWiki::Filter::_process_template(\$in, $page);
  INDENT -1;
  return $out;
}


sub _process_template
{
  my $process_in = shift;
  my $page = shift;

  my %tt_opt;
  foreach my $key (keys %$page) {
    next unless $key =~ /^TT_/;
    my $val = $page->{$key};
    $key =~ s/^TT_//;
    $tt_opt{$key} = $val;
    TRACE "TemplateToolkit option: $key=$val";
  }

  my $out = "";
  my $tt = Template->new(\%tt_opt);
  $tt->process($process_in, $page, \$out) or ERROR("Template Error: " . $tt->error());

  return $out;
}

1;
