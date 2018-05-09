package Apache::FileWiki::Handler;

use strict;
use warnings;

use FileWiki;
use FileWiki::Logger;

use Apache2::Const -compile => qw(OK);
use Apache2::Request;

use File::MimeInfo qw(globs);


=head1 NAME

Apache::FileWiki::Handler - Apache Handler for FileWiki pages

=head1 SYNOPSIS

    <LocationMatch "^/filewiki/.*\.html$">
        SetHandler perl-script
        PerlResponseHandler Apache::FileWiki::Handler

        # base directory of the source files
        PerlSetVar BASEDIR "/var/www/localhost/htdocs/example.org"

        # prefix the link URI's, so that we access the files from:
        # http://127.0.0.1/filewiki/example.org
        PerlSetVar URI_PREFIX "/filewiki/example.org"

        # accept localhost only, this code is NOT secure!
        Order deny,allow
        Deny from all
        Allow from 127.0.0.1
    </LocationMatch>

=head1 DESCRIPTION

Experimental web frontend to FileWiki. Works together with templates
found in "example.org/templates/filewiki/". Supports modifying
FileWiki pages and vars, issuing CMS commands and showing log and vars
for debugging reasons.

B<NOTE: This handler is not secure at all! Do NOT make it accessible
on a publicly available location!> It does NOT check input and output
files in any ways, thus allowing read and write operations on EVERY
file on your filesystem (of course limited to the user/group
permissions of your web server).

The full FileWiki documentation is available at L<https://digint.ch/filewiki>.

=head1 TODO

=over

=item * Support cookies, for generic CMS input fields, logger settings, ...

=back


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

=cut


# This might be a problem, since signals are not thread-safe.
# Not sure though if __WARN__ is really a signal or just a perl internal thingy.
#BEGIN {
#  # log perl warnings to FileWiki::Logger
#  $SIG{__WARN__} = sub { WARN "@_\n"; }
#}


sub handler {
  my $r = shift;
  my %vars = ( filewiki_controls => 1,
               BASEDIR           => $r->dir_config('BASEDIR'),
               URI_PREFIX        => $r->dir_config('URI_PREFIX'),
               CMS_USERNAME      => "",
               CMS_PASSWORD      => "",
               CMS_TEXT          => "",
             );
  my $uri = $r->uri();
  die("No BASEDIR provided (hint: \"PerlSetVar BASEDIR /my/dir/\" in apache config)") unless $vars{BASEDIR};
  ClearLog();

  # all request parameters go into vars
  my $apr = Apache2::Request->new($r);
  my @keys = $apr->param;
  foreach my $key (@keys) {
    my @value = $apr->param($key);
    next unless scalar @value;
    WARN "Multiple values for apache request key=\"$key\": values=[ @value ], using \"$value[0]\"" if(@value > 1);
    $vars{$key} = $value[0];
  }

  # write a file (page source or vars file)
  # NOTE: this is very insecure, we do no checking at all!
  if($vars{filewiki_save} && $vars{filewiki_submit_file} && $vars{filewiki_submit_text})
  {
    my $file = $vars{filewiki_submit_file};
    INFO "Writing file: $file";
    if(open(OUTFILE, ">$file"))
    {
      print OUTFILE $vars{filewiki_submit_text};
      close(OUTFILE);

      $vars{filewiki_info_msg} = "Wrote file: $file";
    } else {
      $vars{filewiki_error_msg} = "Failed to write file '$file': $!";
      ERROR "Failed to write file '$file': $!";
    }
  }

  # install site
  if($vars{filewiki_command})
  {
    my $fw = FileWiki->new(%vars);
    my ($err, $msg, $output) = $fw->command($vars{filewiki_command});
    $vars{filewiki_cmd_output} = $output;
    if($err) {
      $vars{filewiki_error_msg} = "Failed to install site: $msg";
    } else {
      $vars{filewiki_info_msg} = "Site successfully installed: $msg";
    }
  }

  my $page_preview = $vars{filewiki_preview} ? $vars{filewiki_submit_text} : undef;
  my $filewiki = FileWiki->new(%vars);
  my $html = $filewiki->page($uri, $page_preview);

  if($html)
  {
    my $page_vars = $filewiki->page_vars($uri);
    my $type = globs("dummy." . $page_vars->{TARGET_TYPE}) || 'text/plain';
    INFO "Setting magic MIME-Type: $type";
    $r->content_type($type) if($type);
  }
  else
  {
    $html = GetLog(format => 'html');
    $r->content_type('text/html');
  }

  my $length = length $html;
  $r->set_content_length($length);

  print $html;
  return Apache2::Const::OK;
}

1;
