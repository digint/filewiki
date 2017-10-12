package FileWiki::Logger;

use strict;
use warnings;

use HTML::Entities;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( LOG INDENT ERROR WARN INFO DEBUG TRACE GetLog ClearLog );

our $VERSION = "0.10";


=head1 NAME

FileWiki::Logger - buffered logging framework

=head1 SYNOPSIS

    use FileWiki::Logger;

    # enable stdout immediate logging
    $FileWiki::Logger::loglevel = $FileWiki::Logger::level{info};

    ERROR "error msg";
    WARN  "warn msg";
    INFO  "info msg";
    DEBUG "debug msg";
    TRACE "trace msg";

    # print all logs in text format
    print GetLog();

    # print warnings and errors only, in html format:
    print GetLog(level => $FileWiki::Logger::level{warn},
                 format => 'html');

=head1 DESCRIPTION

Simple logging framework. Main feature is to log into a global buffer,
which can be retrieved in several formats on demand.

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


our %level = ( off   => -1,
               error => 0,
               warn  => 1,
               info  => 2,
               debug => 3,
               trace => 4
              );


our %prefix = ( stdout  => [ "E  ", "W  ", "I  ", "D  ", "T  " ],
                html    => [ '<code class="log_e">E&nbsp;',
                             '<code class="log_w">W&nbsp;',
                             '<code class="log_i">I&nbsp;',
                             '<code class="log_d">D&nbsp;',
                             '<code class="log_t">T&nbsp;',
                            ],
               );

our %postfix = ( stdout  => ["\n", "\n", "\n", "\n", "\n" ],
                 html    => [ "<br/></code>\n",
                              "<br/></code>\n",
                              "<br/></code>\n",
                              "<br/></code>\n",
                              "<br/></code>\n",
                             ],
                );

our %indent = ( stdout  => '  ',
                html    => '&nbsp;',
               );

our %filter = ( stdout => undef,
                html    => sub { return encode_entities(@_); },
               );

our @logger;          # ( [ level, indent, text ], ... )
our $loglevel = -1;   # do not log to stdout by default

my $indent_level = 0;


sub ClearLog
{
  @logger = ();
  $indent_level = 0;
}

sub GetLog
{
  my %args = @_;
  my $format  = $args{format}  || 'stdout';
  my $level   = $args{level}   || 10;
  my $indent  = $args{indent}  || $indent{$format};
  my $prefix  = $args{prefix}  || $prefix{$format};
  my $postfix = $args{postfix} || $postfix{$format};
  my $filter  = $args{filter}  || $filter{$format};
  my $ret = '';

  foreach my $log (@logger) {
    my $ll = $log->[0];
    next if($level < $ll);
    my $line = $log->[2];
    $line = &$filter($line) if($filter);
    $ret .= $prefix->[$ll] . ($indent x $log->[1]) . $line . $postfix->[$ll];
  }
  return $ret;
}


sub INDENT
{
  $indent_level += shift;
}


sub LOG
{
  my $ll = shift;
  my $text = shift;
  my %args = @_;

  if($text) {
    foreach my $line (split(/\n/, $text)) {
      push(@logger, [ $ll, $indent_level, $line ]);
      print $prefix{stdout}->[$ll] . ($indent{stdout} x $indent_level) . $line . $postfix{stdout}->[$ll] if($ll <= $loglevel);
    }
  }
  INDENT $args{indent} if($args{indent});
  return $text;
}
sub ERROR { return LOG(0, @_); }
sub WARN  { return LOG(1, @_); }
sub INFO  { return LOG(2, @_); }
sub DEBUG { return LOG(3, @_); }
sub TRACE { return LOG(4, @_); }

1;
