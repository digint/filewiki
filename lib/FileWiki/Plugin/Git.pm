=head1 NAME

FileWiki::Plugin::Git - Git variable provider plugin for FileWiki

=head1 SYNOPSIS

    PLUGINS=Git

=head1 DESCRIPTION

Provides page variables from source files under git control.

=head1 CONFIGURATION VARIABLES

=head2 PLUGIN_GIT_MATCH

Defines a match on file names for the git plugin. The git plugin will only be
enabled if the file matches the expression. Defaults to '.*' (all files).

=head2 GIT_BIN

Git binary, defaults to 'git'.

=head2 GIT_TIME_FORMAT

Time format to be used for dates. Corresponds to the C library
routines "strftime" and "ctime". Defaults to TIME_FORMAT page
variable, which again defaults to "%C".

=head1 VARIABLE PRESETS

=head2 GIT_COMMIT_HASH

The git "commit hash" of the source file.

=head2 GIT_AUTHOR_NAME

The git "author name" of the source file.

=head2 GIT_AUTHOR_EMAIL

The git "author email" of the source file.

=head2 GIT_AUTHOR_DATE

The git "author date" of the source file, formatted by the GIT_TIME_FORMAT variable.

=head2 GIT_AUTHOR_DATE_UNIX

The git "author date" of the source file, UNIX timestamp.

=head2 GIT_COMMITTER_NAME

The git "committer name" of the source file.

=head2 GIT_COMMITTER_EMAIL

The git "committer email" of the source file.

=head2 GIT_COMMITTER_DATE

The git "committer email" of the source file, formatted by the GIT_TIME_FORMAT variable.

=head2 GIT_COMMITTER_DATE_UNIX

The git "committer email" of the source file, UNIX timestamp.

=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2017 Axel Burri. All rights reserved.

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


package FileWiki::Plugin::Git;

use strict;
use warnings;

use base qw( FileWiki::Plugin );

use FileWiki::Logger;
use Date::Format qw(time2str);


our $VERSION = "0.50";

our $MATCH_DEFAULT = '.*';

my $git_bin_default = 'git';

my @git_log_format = (
  { format => '%H',  key => 'GIT_COMMIT_HASH'                                            },

  { format => '%an', key => 'GIT_AUTHOR_NAME'                                            },
  { format => '%ae', key => 'GIT_AUTHOR_EMAIL'                                           },
  { format => '%at', key => 'GIT_AUTHOR_DATE_UNIX'   , key_date => 'GIT_AUTHOR_DATE'     },

  { format => '%cn', key => 'GIT_COMMITTER_NAME'                                         },
  { format => '%ce', key => 'GIT_COMMITTER_EMAIL'                                        },
  { format => '%ct', key => 'GIT_COMMITTER_DATE_UNIX', key_date => 'GIT_COMMITTER_DATE'  },
 );


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
  my $cmd = $page->{GIT_BIN} || $git_bin_default;
  $cmd .= ' log -1 --format="';
  $cmd .= $_->{format} . '%n'  foreach (@git_log_format);
  $cmd .= '" "' . $file . '"';

  DEBUG "$cmd";
  my $ret = `$cmd`;
  ERROR "Command execution failed ($?): $cmd" if($?);

  my $time_format = $page->{GIT_TIME_FORMAT} || $page->{TIME_FORMAT} || '%C';
  my $n = 0;
  foreach my $row (split("\n", $ret)) {
    my $key      = $git_log_format[$n]->{key};
    my $key_date = $git_log_format[$n]->{key_date};
    $page->{$key} = $row;
    $page->{$key_date} = time2str($time_format, $row) if($key_date);
    $n++;
  }
}


1;
