package Template::Plugin::FileWiki;

use strict;
use warnings;

use base qw( Template::Plugin );

use FileWiki;
use HTML::Entities;
use FileWiki::Logger;

our $VERSION = "0.40";

=head1 NAME

Template::Plugin::FileWiki - FileWiki plugin for Template Toolkit

=head1 SYNOPSIS

Usage in Template:

  [% USE FileWiki %]

  [% FileWiki.PageTree( <arguments...> ) %]
  [% FileWiki.PageList( <arguments...> ) %]

  [% FileWiki.Sitemap %]
  [% FileWiki.DumpVars %]
  [% FileWiki.Log %]


=head1 DESCRIPTION

FileWiki plugin for Template Toolkit.

Provides functions for displaying information from a FileWiki site
structure from within a template.

=head1 METHODS


=head2 PageTree

Generate a HTML list (with sublists) of all pages, starting at ROOT
node. Provides a flexible way to recurse into all pages.

See L</Generic Function Arguments> below for the arguments taken.

Example:

  [% FileWiki.PageTree( text_key  => "menu",
                        title_key => "menu_title",
                        depth     => 2,
                        collapse  => 1 )
  %]

This displays a collapsed menu with a depth of 2, showing the page-var
"menu" as link text and "menu_title" as link title.


=head2 PageList

Generate a flat HTML list of all pages, starting at ROOT node.

See L</Generic Function Arguments> below for the arguments taken.

Example:

  [% FileWiki.PageList(
        match    => { IS_DIR => '0',
                      SRC_FILE => "^$libdir/.*\.pm$" },
        text_key => 'SRC_FILE',
        regexp   => [ { match => "^$libdir/", replace => ''   },
                      { match => '\.pm$',     replace => ''   },
                      { match => '/',         replace => '::' } ],
     )
  %]

This shows a list of all perl modules in "libdir" (page-var),
reformatted in perl notation (Example::TestModule).

=head2 PageArray

Returns an array of pointers to page hash
See L</Generic Function Arguments> below for the arguments taken.

Example:

  [% FileWiki.PageArray(
        match    => { IS_DIR => '0',
                      SRC_FILE => "^$libdir/.*\.pm$" },
        text_key => 'SRC_FILE',
        regexp   => [ { match => "^$libdir/", replace => ''   },
                      { match => '\.pm$',     replace => ''   },
                      { match => '/',         replace => '::' } ],
     )
  %]

This shows a list of all perl modules in "libdir" (page-var),
reformatted in perl notation (Example::TestModule).


=head2 Sitemap

Displays a Sitemap of all pages, with useful information such as
source file and source file type.
Useful when creating a site.

Takes only the "ROOT" argument from  L</Generic Function Arguments>.


=head2 DumpVars

Displays all vars of a page. Takes a page as argument.
Useful when creating a site.


=head2 Log

Displays the FileWiki log.


=head1 Generic Function Arguments

Arguments for the L</PageTree> and L</PageList> functions.

=over

=item ROOT

The root node, must be a directory node.
Defaults to site root.

=item page_current

The page to be considered as currently displayed.
Affects the highlight and collapse behaviour.
Defaults to current page.

=item depth

If set, stops traversing directories at deeper levels.

=item collapse

If set, displays only top-level directories and the pages which are on
the same level as the current page (see page_current above).
Useful for menu.
Defaults to false.

=item text_key

The page-var key to be displayed in the link. Pages with this key not
set are not displayed.
Defaults to "NAME" in PageTree, and "URI" in PageList.

=item text_key_dir_alt

The dir-var key to be displayed in the link for directories if the
text_key is not set.  Useful if you want to make sure that all
directories are displayed in the PageTree.
Defaults to undef.

=item title_key

The page-var key to be set as "title" attribute in the link.
Defaults to undef.

=item highlight_link

If set, tag the link of the current page with class "highlight".
Defaults to false.

=item highlight_list_item

If set, tag the list item of the current page with class "highlight".
Defaults to false.

=item highlight_parents

If set, also tag all parents of the current page with class "highlight".
Defaults to false.

=item list_item_class_key

The page-var key to be set as "class" attribute in the list item
element.
Defaults to undef.

=item match

Hash reference to match expressions: the key defines the page-var, the
value defines the match expression. A page is only displayed in the
list if ALL the matches succeed. If not set, all pages are displayed.

Example (display pages from authors from "tty0.ch", no directories):

  match => { IS_DIR => '0',
             author => "<.*@tty0.ch>" },

=item regexp

Reference a hash reference, or array reference to array of hash
references.
Perform replace regexp on displayed text (given by text_key).

Example (display perl modules in perl-style):

  regexp => [ { match => "^$libdir/", replace => ''   },
              { match => '\.pm$',     replace => ''   },
              { match => '/',         replace => '::' } ],


=back

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


sub highlight
{
  my $page = shift;
  my $args = shift;
  my $page_current = $args->{page_current};

  # highlight target page
  my $highlight = ($page_current && ($page_current->{URI} eq $page->{URI}));

  # highlight parent directory
  $highlight ||= $args->{highlight_parents} && $page->{IS_DIR} && $page_current && exists($page->{PAGEHASH}->{$page_current->{URI}});

  # max depth is reached, and current page is subpage
  $highlight ||= ((exists($args->{depth}) && ($args->{depth} == $page->{LEVEL})) &&
                  $page->{IS_DIR} && $page_current && exists($page->{PAGEHASH}->{$page_current->{URI}}));

  return $highlight;
}


sub page_link
{
  my $page = shift;
  my $args = shift;
  my $uri = $page->{INDEX_PAGE}->{URI} || $page->{URI}; # directories point to their index_page

  # set text and title
  my $text_key = $args->{text_key};
  my $title_key = $args->{title_key};
  my $text = $page->{$text_key};
  my $title = $title_key ? $page->{$title_key} : '';

  my $text_key_dir_alt = $args->{text_key_dir_alt};
  unless($text) {
    # set alternative text for directories
    if($page->{IS_DIR} && $text_key_dir_alt) {
      $text = $page->{$text_key_dir_alt};
      $text =~ s/_/ /g;
      DEBUG "Undefined variable \"$text_key\", using alternative $text_key_dir_alt=\"$text\": $uri";
    } else {
      TRACE "Skipping item (undefined \"$text_key\"): $uri";
      return "";
    }
  }

  # process regexp
  $text =~ s/$_->{match}/$_->{replace}/g  foreach (@{$args->{regexp}});

  DEBUG "Creating link item \"$text\": $uri";

  # create the html link
  my $html;
  $html .= "<a href=\"$uri\"";
  $html .= " title=\"$title\""     if($title);
  $html .= " class=\"highlight\""  if($args->{highlight_link} && highlight($page, $args));
  $html .= ">";
  $html .= "$text";
  $html .= "</a>\n";

  return $html;
}

sub tree_item
{
  my $page = shift;
  my $args = shift;
  my %flags = @_;
  my $prev_level = $args->{prev_level};
  my $tag_stack = $args->{tag_stack};
  my $level = $page->{LEVEL};

  my $html = '';
  my $item_html = page_link($page, $args);
  return ""  unless($item_html);

  if(($$prev_level < $level)) {
    $html .= '<ul';
    $html .= ' class="collapse"' if($flags{collapse});
    $html .= '>';
    push @$tag_stack, '</ul>';
  }
  elsif($$prev_level == $level) {
    $html .= pop @$tag_stack; # /li
  }
  elsif($$prev_level > $level) {
    $html .= pop @$tag_stack; # /li
    for(my $i = $$prev_level; $i > $level; $i--) {
      $html .= pop @$tag_stack; # /ul
      $html .= pop @$tag_stack; # /li
    }
  }

  my @classes;
  push(@classes, 'highlight') if($args->{highlight_list_item} && highlight($page, $args));
  if($args->{list_item_class_key}) {
    my $cc = $page->{$args->{list_item_class_key}};
    push(@classes, ref($cc) ? @$cc : $cc) if($cc);
  }

  $html .= '<li';
  $html .= ' class="' . join(' ', @classes) . '"' if(scalar(@classes));
  $html .= '>';
  push @$tag_stack, '</li>';

  $html .= $item_html;

  $$prev_level = $level;

  return $html;
}


sub list_item
{
  my $page = shift;
  my $args = shift;

  my $link = page_link($page, $args);
  return "" unless($link);

  my $html = '';
  $html .= '<li';
  $html .=  ' class="highlight"' if($args->{highlight_list_item} && highlight($page, $args));
  $html .= '>';
  $html .= $link;
  $html .= '</li>';
  return $html;
}


sub set_default_list_args
{
  my $page = shift;
  my $args = shift;
  $args->{ROOT}         ||= $page->{ROOT};
  $args->{page_current} ||= $page;

  $args->{regexp} = [ $args->{regexp} ] if(exists($args->{regexp}) && (ref $args->{regexp} ne "ARRAY"));
}


sub PageArray
{
  my $self = shift;
  my $args = shift;
  my $page = $self->{_CONTEXT}->{STASH};

  $args->{ROOT} ||= $page->{TREE};
  my @ret = ();
  $args->{CALLBACK} = sub {
    my $page = shift;
    push @ret, $page;
    return "";
  };
  FileWiki::traverse($args);
  return \@ret;
}


sub PageList
{
  my $self = shift;
  my $args = shift;
  my $page = $self->{_CONTEXT}->{STASH};

  set_default_list_args($page, $args);
  $args->{text_key} ||= 'URI';
  $args->{CALLBACK} = \&list_item;

  DEBUG "Creating PageList: $args->{ROOT}->{URI}"; INDENT 1;

  my $html;
  $html .= "<ul>";
  $html .= FileWiki::traverse($args);
  $html .= "</ul>";

  INDENT -1;

  return $html;
}


sub PageTree
{
  my $self = shift;
  my $args = shift;
  my @tag_stack;
  my $page = $self->{_CONTEXT}->{STASH};

  set_default_list_args($page, $args);
  $args->{text_key} ||= "NAME";
  $args->{CALLBACK} = \&tree_item;
  $args->{tag_stack} = \@tag_stack;

  DEBUG "Creating PageTree: $args->{ROOT}->{URI}"; INDENT 1;
  my $html = FileWiki::traverse($args);
  INDENT -1;

  $html .= pop @tag_stack while(@tag_stack);
  return $html;
}


sub page_info
{
  my $page = shift;
  my $args = shift;
  my $indent = $page->{LEVEL} - $args->{init_level} - 1;

  my $name = $page->{URI};
  $name =~ s/.*\/([^\/]+)/$1/;

  my $uri = $page->{URI};
  $uri =~ s/^$page->{URI_PREFIX}//;

  my $ret = '<tr>';
  $ret .= "<td>";
  $ret .= ("&nbsp;&nbsp;" x $indent);
  $ret .= "<a href=\"$page->{URI}\">";
  $ret .= $name;
  $ret .= "</a>";
  $ret .= "</td>";
  $ret .= "<td>";
  $ret .= "<a href=\"$page->{URI}\">";
  $ret .= $uri;
  $ret .= "</a>";
  $ret .= "</td>";
  $ret .= "<td>";
  $ret .= $page->{SRC_FILE};
  $ret .= "</td>";
  $ret .= "<td>";
  $ret .= $page->{IS_DIR} ? "[DIR]" : "[$page->{HANDLER}->{name}]";
  $ret .= "</td>";
  $ret .= "</tr>";

  $ret =~ s/$page->{BASEDIR}\/?//g;


  return $ret;
}


sub Sitemap
{
  my $self = shift;
  my $args = shift;
  my $page = $self->{_CONTEXT}->{STASH};
  $args->{CALLBACK} = \&page_info;

  $args->{ROOT} ||= $page->{ROOT};

  my $html;
  $html .= '<table><tbody>';
  $html .= "<tr>";
  $html .= "<th>Tree</th>";
  $html .= "<th>URI</th>";
  $html .= "<th>Source File</th>";
  $html .= "<th>Type</th>";
  $html .= "</tr>";
  $html .= FileWiki::traverse($args);
  $html .= '</table></tbody>';

  return $html;
}


sub DumpVars
{
  my $self = shift;
  my $vars = shift || $self->{_CONTEXT}->{STASH};
  return encode_entities(FileWiki::dump_vars($vars));
}

sub Log
{
  my $self = shift;
  my $args = shift;

  $args->{format} ||= 'html';
  return GetLog(%$args);
}


1;

