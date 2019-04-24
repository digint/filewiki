=head1 NAME

FileWiki::Plugin::Perl - Perl variable provider plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Perl

=head1 DESCRIPTION

Provides page variables from perl source files.

=head1 CONFIGURATION VARIABLES

=head2 PLUGIN_PERL_MATCH

Defines a match on file names for the perl plugin. The perl plugin
will only be enabled if the file matches the expression. Defaults to
'.pm'.

=head2 PERL_PACKAGE

The perl package namespace if 'package foo::bar' line is present.

=head2 PERL_VERSION

The package version '$VERSION = xxx' line is present.

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


package FileWiki::Plugin::Perl;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;

our $VERSION = "0.50";

our $MATCH_DEFAULT = '\.pm$';


sub new
{
  my $class = shift;
  my $page = shift;
  my $args = shift;

  my $self = {
    name => $class,
    vars_provider => 1,
  };

  bless $self, ref($class) || $class;
  return $self;
}

sub update_vars
{
  my $self = shift;
  my $page = shift;
  my $file = $page->{SRC_FILE};

  DEBUG "Parsing perl module: $file"; INDENT 1;

  my $fh;
  open($fh, "<$file") or die "Failed to open file \"$file\": $!";

  my $package = "";
  my $version = "";
  while (<$fh>) {
    chomp;
    if(/^package\s+(\w+(::\w+)*)/) {
      $package = $1;
    }
    if(/\$VERSION\s*=\s*(.*);/) {
      $version = $1;
      $version =~ s/\s*$//;
      $version =~ s/^['"]//;
      $version =~ s/['"]$//;
    }
    last if($package && $version)
  }
  close $fh;

  if($package) {
    DEBUG "Setting PERL_PACKAGE=\"$package\"";
    $page->{PERL_PACKAGE} = $package;
  }
  else {
    WARN "Failed to parse package: $file";
  }

  DEBUG "Setting PERL_VERSION=\"$version\"";
  $page->{PERL_VERSION} = $version;

  INDENT -1;
}


1;
