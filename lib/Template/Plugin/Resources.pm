package Template::Plugin::Resources;

use strict;
use warnings;

use base qw( Template::Plugin );

use FileWiki::Logger;

our $VERSION = "0.53";

=head1 NAME

Template::Plugin::Resources - Resources plugin for Template Toolkit

=head1 SYNOPSIS

Usage in Template:

  [% USE Resources %]

  [% Resources.list() %]


=head1 DESCRIPTION

Provides helper functions for FileWiki RESOURCES.

=head1 METHODS

=head2 list

Returns a sorted / filtered list of resources.

Arguments:

 - type: filter type portion from MIME_TYPE ("type/subtype")
 - sort: sort order of subtype (second part of MIME_TYPE)
 - base: hashref containing RESOURCE hash (defaults to $page)


=head1 AUTHOR

Axel Burri <axel@tty0.ch>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2011-2018 Axel Burri. All rights reserved.

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

=head1 SEE ALSO

Template Toolkit Plugin Documentation:

L<http://www.template-toolkit.org/docs/modules/Template/Plugin.html>

=cut


sub new {
  my ($class, $context, @params) = @_;

  bless {
    _CONTEXT => $context,
  }, $class;
}


sub list
{
  my $self = shift;
  my $args = shift;
  my $page = $self->{_CONTEXT}->{STASH};
  my $type = $args->{type} || die;
  my $base = $args->{base} || $page;
  my $sort_order = $args->{sort};
  my $resources = $base->{RESOURCE};

  return undef unless($resources);

  my @filtered = grep { $_->{MIME_TYPE} =~ /^$type\// } values %$resources;

  return undef unless(scalar(@filtered));

  return \@filtered unless($sort_order);

  my %order_map = map { $sort_order->[$_] => $_ } 0 .. $#$sort_order;
  my @sorted = sort {
    my ($x, $y) = map /^$type\/([^;]+)/, $a->{MIME_TYPE}, $b->{MIME_TYPE};
    (($order_map{$x} // 0) <=> ($order_map{$y} // 0)) || ($x cmp $y)
  } @filtered;

  return \@sorted;
}

1;
