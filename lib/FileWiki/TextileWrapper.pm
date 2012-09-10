package FileWiki::TextileWrapper;

use strict;
use warnings;

use Text::Textile;

use base 'Text::Textile';
our $VERSION = "0.10";


=head1 NAME

FileWiki::TextileWrapper - Wrapper around Text::Textile

=head1 DESCRIPTION

Simple wrapper around Text::Textile, overriding the format_link
function in order to provide access to FileWiki default links.

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

sub format_link {
    my $self = shift;

    $self->{links} = { %{$self->{default_links}},
                       %{$self->{links}}
                      };

    return $self->SUPER::format_link(@_);
}

1;
