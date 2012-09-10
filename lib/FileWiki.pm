package FileWiki;

use strict;
use warnings;

use FileWiki::Logger;

use Date::Format qw(time2str);
use Time::Piece;
use File::Path qw(mkpath);
use File::Spec::Functions qw(splitpath);

use Template;

our $VERSION = "0.10";

# Defaults
our $dir_vars_filename = 'dir.vars';
our $tree_vars_filename = 'tree.vars';
our $default_target_type = 'html';
our $default_time_format = '%C';

#
# Source type definition:
#
#  - match: regular expression (defaults to the hash key as file ending)
#  - filter: arrayref of chained filter functions
#  - target_type: target file extension (defaults to 'html')
#  - nested_vars: if true, parse the <filewiki_vars> section in the document
#
our %doctype = (
  markdown => { match  => '\.(markdown|txt)$',
                filter => [
                           \&sanitize_newlines,
                           \&strip_nested_vars,
                           \&strip_xml_comments,
                           \&transform_markdown,
                           \&apply_template,
                          ],
                nested_vars => 1,
              },
  textile  => { match  => '\.(textile)$',
                filter => [
                           \&sanitize_newlines,
                           \&strip_nested_vars,
                           \&strip_xml_comments,
                           \&transform_textile,
                           \&apply_template,
                          ],
                 nested_vars => 1,
               },
  template =>  { match  => '\.(tt)$',
                 filter => [
                            \&sanitize_newlines,
                            \&strip_nested_vars,
                            \&transform_template,
                            \&apply_template,
                           ],
                 nested_vars => 1,
               },
  pod      =>  { match  => '\.(pod|pm|pl)$',
                 filter => [
                            \&sanitize_newlines,
                            \&transform_pod,
                            \&apply_template,
                           ],
                 nested_vars => 1,
               },
  html      => { filter => [
                            \&sanitize_newlines,
                            \&apply_template,
                           ],
               },
 );

=head1 NAME

FileWiki - File based web site generator

=head1 SYNOPSIS

    use FileWiki;
    my $filewiki = FileWiki->new(BASEDIR => "example.org");

    $filewiki->create();              # create all pages
    $filewiki->create(@uri_list);     # create list of pages
    $filewiki->command("mycommand");  # run generic command: CMD_MYCOMMAND

    # get html output for a single page
    my $html = $filewiki->page($uri);

=head1 DESCRIPTION

FileWiki is a simple but powerful web site generator.
It parses a directory tree and generates static web pages defined by
templates, which make use of variables seeded within the tree.

The full documentation is available at L<http://www.digint.ch/filewiki/>.

=head1 BUGS

Please file bug reports directly to the author.

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

sub new
{
  my ($class, %vars) = @_;

  die "missing argument 'BASEDIR'" unless($vars{BASEDIR});
  $vars{BASEDIR} =~ s/\/$//; # strip trailing slash

  my $self = { version => $VERSION,
               vars => { URI_PREFIX => "",
                         BUILD_TIME => time,
                         %vars,
                         ENV => \%ENV,
                       },
              };

  bless $self, ref($class) || $class;

  INFO "FileWiki v$VERSION";
  TRACE "Initial vars:"; INDENT 1;
  TRACE dump_vars($self->{vars}); INDENT -1;

  return $self;
}


sub eval_module
{
  my $module = shift;
  my $msg = shift;
  unless(eval "require $module;") {
    ERROR "Perl module \"$module\" not found! $msg";
    DEBUG "$@";
    return 0;
  }
  return 1;
}


sub check_var
{
  my ($vars, $key, $file) = @_;
  unless(exists($vars->{$key})) {
    WARN "Variable \"$key\" is not defined in $file line $.\n";
    return "<undef>";
  }
  return $vars->{$key};
}


sub read_vars
{
  my %args = @_;
  my $file = $args{file};
  die "missing argument 'file'" unless($file);
  my $nested_remove_char = "";
  my %vars;
  %vars = %{$args{vars}} if($args{vars});

  $vars{VARS_FILES} = ($vars{VARS_FILES} ? $vars{VARS_FILES} . "\n" : "") .  $file unless($args{nested});

  return %vars unless(-r "$file");

  DEBUG "Reading " . ($args{nested} ? "nested" : "") . " vars: $file"; INDENT 1;

  open(FILE, "<$file") or die "Failed to open file \"$file\": $!";

  if($args{nested}) {
    my $found = 0;
    while (<FILE>) {
      if( /^(.?)[<\[]filewiki_vars[>\]]/ ) {
        $nested_remove_char = $1;
        $found = 1;
        last;
      }
    }

    unless($found) {
      DEBUG "No nested vars found"; INDENT -1;
      close FILE;
      return %vars;
    }
  }

  while (<FILE>) {
    chomp;
    s/^$nested_remove_char//;
    last if /^[<\[]\/filewiki_vars[>\]]/;
    next if /^\s*\#/;
    next if /^\s*$/;
    my ($key, $val) = /^\s*(\w+)[\s=]+(.*?)\s*$/;

    unless($key) {
      WARN "Ambiguous variable declaration: $file line $.";
      next;
    }

    # store raw value before expanding
    $vars{VARS_PRE_EXPAND} = { } unless exists $vars{VARS_PRE_EXPAND};
    $vars{VARS_PRE_EXPAND}->{$key} = $val;

    if($val =~ /^\$(\w+)$/) {
      # directly assignment (important to assign references)
      $vars{$key} = check_var(\%vars, $1, $file);
      next;
    }

    # remove quotes
    $val =~ s/^"//;
    $val =~ s/"$//;

    # expand variables
    $val =~ s/\${(\w+)}/check_var(\%vars, $1, $file)/eg;
    $val =~ s/\$(\w+)/check_var(\%vars, $1, $file)/eg;

    $vars{$key} = $val;
    TRACE "$key=$val";

  }
  INDENT -1;
  close(FILE);
  return %vars;
}


sub strip_nested_vars
{
  my $self = shift;
  my $in = shift;
  my $page = shift;
  return $in unless(exists($doctype{$page->{SRC_TYPE}}) && 
                    $doctype{$page->{SRC_TYPE}}->{nested_vars});
  DEBUG "Stripping page nested vars";

  $in =~ s/^.?[<\[]filewiki_vars[>\]].*?^.?[<\[]\/filewiki_vars[>\]]//ms;

  return $in;
}


sub strip_xml_comments
{
  my $self = shift;
  my $in = shift;
  my $page = shift;
  DEBUG "Stripping xml-style comments";

  $in =~ s/<!----.*?---->//sg;

  return $in;
}


sub sanitize_newlines
{
  my $self = shift;
  my $in = shift;
  DEBUG "Sanitizing newlines";
  $in =~ s/\r\n/\n/g;
  return $in;
}


sub transform_markdown
{
  my $self = shift;
  my $in = shift;
  my $r = $self->refs();
  my %refs = %$r; # make a copy, markdown modifies these

  DEBUG "Converting Markdown";

  return $in unless(eval_module('Text::Markdown', 'Skipping Markdown conversion.'));
  return Text::Markdown::markdown($in, { urls => \%refs });
}

sub transform_textile
{
  my $self = shift;
  my $in = shift;
  DEBUG "Converting Textile";

  return $in unless(eval_module('Text::Textile', 'Skipping Textile conversion.'));
  return $in unless(eval_module('FileWiki::TextileWrapper', 'Skipping Textile conversion.'));

  my $refs = $self->refs();
  my $ti = Text::Textile::DefaultLinks->new();
  # set the link references for Textile
  $ti->{default_links}{$_} = { url => $refs->{$_}, title => undef } foreach (keys %$refs);
  return $ti->process($in);
}

sub transform_pod
{
  my $self = shift;
  my $in = shift;
  DEBUG "Converting POD";

  return $in unless(eval_module('Pod::Simple::HTML', 'Skipping POD conversion.'));

  my $out = '';
  my $parser = Pod::Simple::HTML->new();

  $parser->output_string(\$out);
  $parser->parse_string_document($in);

  $out =~ s/.*\<\!-- start doc --\>//ms;
  $out =~ s/\<\!-- end doc --\>.*//ms;
  return $out;
}

sub transform_template
{
  my $self = shift;
  my $in = shift;
  my $page = shift;

  DEBUG "Converting template"; INDENT 1;
  my $out = _apply_template(\$in, $page);
  INDENT -1;
  return $out;
}

sub apply_template
{
  my $self = shift;
  my $in = shift;
  my $page = shift;

  unless($page->{TEMPLATE}) {
    ERROR "'TEMPLATE' variable not specified: $page->{SRC_FILE}";
    return $in;
  }

  DEBUG "Processing template: $page->{TEMPLATE}"; INDENT 1;
  $page->{TEMPLATE_INPUT} = $in;
  my $out = _apply_template($page->{TEMPLATE}, $page);
  INDENT -1;
  return $out;
}

sub _apply_template
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

  my $tt = Template->new(\%tt_opt);

  my $out = "";
  $tt->process($process_in, $page, \$out) or ERROR("Template Error: " . $tt->error());
  return $out;
}

sub process_page
{
  my $self = shift;
  my $page = shift;
  my $data = shift;
  my $root = $self->site_tree();

  my $sfile = $page->{SRC_FILE};

  return unless($sfile);

  INFO "Processing page: $page->{URI}"; INDENT 1;

  if($data)
  {
    DEBUG "Got " . length($data) . " bytes of dynamic data, ignoring input file.";
  }
  else
  {
    DEBUG "Reading file: $sfile";
    open(INFILE, "<$sfile") or die "Failed to open file \"$sfile\": $!";
    {
      local $/;			# slurp the file
      $data = <INFILE>;
    }
    close(INFILE);
  }

  $page->{SRC_TEXT} = $data;

  unless($page->{SRC_TYPE} eq 'RAW')
  {
    DEBUG "Processing filter chain \"$page->{SRC_TYPE}\""; INDENT 1;
    # process the filter chain
    foreach my $filter_function (@{$doctype{$page->{SRC_TYPE}}->{filter}})
    {
      TRACE "Data length=" . length($data);
      $data = &$filter_function($self, $data, $page);
    }
    TRACE "Data length=" . length($data);
    INDENT -1;
  }

  INDENT -1;
  return $data;
}


sub set_uri
{
  my $page = shift;

  # sanitize
  $page->{URI_DIR} =~ s/\/+$//;
  $page->{URI_PREFIX} =~ s/\/+$//;
  $page->{URI_PREFIX} =~ s/^([^\/])/\/$1/;

  my $uri = $page->{URI_DIR} . '/';
  unless($page->{IS_DIR}) {
    my $name = $page->{NAME}               || die("No NAME specified");
    my $target_type = $page->{TARGET_TYPE} || die("No TARGET_TYPE specified");
    $uri .= $name . '.' . $target_type;
  }
  $uri = lc($uri) if($page->{URI_TRANSFORM_LC});

  $page->{URI} = $page->{URI_PREFIX} . $uri;
  return $uri;
}


sub _site_tree
{
  my ($src_dir, $uri_dir, %tree_vars) = @_;
  my $level = $tree_vars{LEVEL} || 1;
  my @pagetree;
  my %pagehash;
  my %dirhash;
  my %dir_vars;

  my $dir_index = $uri_dir;
  if($uri_dir =~ s/(\d*)-([^.]+)$/$2/) {
    $dir_index = $1;
    DEBUG "Directory index prefix found: $dir_index";
  }
  my $uri_dirname = $uri_dir;
  $uri_dirname =~ s/.*\///;

  # get overlay prefix for INCLUDE's
  my $vars_overlay;
  foreach my $overlay_dir (keys %{$tree_vars{INCLUDE_VARS}}) {
    if($src_dir =~ /^$overlay_dir(.*)/) {
      $vars_overlay = $1;
      $vars_overlay =~ s/\//_/g;
      $vars_overlay = $tree_vars{INCLUDE_VARS}->{$overlay_dir} . $vars_overlay;
      DEBUG "Found overlay prefix: $vars_overlay";
      last;
    }
  }

  # provide DIR in tree_vars
  %tree_vars = ( %tree_vars,
                 DIR => \%dir_vars );

  # read the tree vars (defaults to upper level tree vars)
  %tree_vars = read_vars(file => "$src_dir/$tree_vars_filename",
                         vars => \%tree_vars);
  %tree_vars = read_vars(file => "$vars_overlay.$tree_vars_filename",
                         vars => \%tree_vars) if($vars_overlay);

  # read the dir vars (no propagation)
  %dir_vars = ( INDEX => $dir_index,
                NAME => $uri_dirname || "ROOT",
                URI_DIR => $uri_dir,
                %tree_vars,
               );

  %dir_vars = read_vars(file => "$src_dir/$dir_vars_filename",
                        vars => \%dir_vars);
  %dir_vars = read_vars(file => "$vars_overlay.$dir_vars_filename",
                        vars => \%dir_vars) if($vars_overlay);

  %dir_vars = ( %dir_vars,
                LEVEL    => $level - 1,
                TREE     => \@pagetree,
                PAGEHASH => \%pagehash,
                DIRHASH  => \%dirhash,
                SRC_FILE => $src_dir,
                IS_DIR   => 1,
               );

  # override $uri_dir with dir_vars{URI_DIR} if set (propagates to subdirs!)
  $uri_dir = set_uri(\%dir_vars);
  TRACE "Dir vars:" ; INDENT 1;
  TRACE dump_vars(\%dir_vars);
  INDENT -1;

  if($dir_vars{SKIP})
  {
    DEBUG "Found dir_vars{SKIP}, skipping directory: $src_dir";
    return undef;
  }

  $tree_vars{ROOT} = \%dir_vars unless($tree_vars{ROOT});

  my @raw_copy = split(/[,;]\s*/, $dir_vars{RAW_COPY}) if($dir_vars{RAW_COPY});

  my @files;
  opendir(my $dh, $src_dir) or die $!; ;
  while(readdir($dh)) {
    if(/^\./) {
      TRACE "skipping dot-file: $src_dir/$_";
      next;
    }
    push @files, "$src_dir/$_";
  }
  closedir $dh;

  # include files/dirs specified in INCLUDE
  if($dir_vars{INCLUDE}) {
    DEBUG "Found dir_vars{INCLUDE}, including files: $dir_vars{INCLUDE}";
    my @includes = split(/[,;]\s*/, $dir_vars{INCLUDE});
    foreach my $include (@includes) {
      $include =~ s/\[(\w+)\]//;

      $tree_vars{INCLUDE_VARS}->{$include} = "$src_dir/$1" if($1);
      push @files, $include;
    }
  }


  foreach my $file (@files)
  {
    $file =~ m/\/([^\/]+)$/;
    my $file_name = $1 || die("uups, '$file' is a directory but does not end with '/*'");

    if(-d $file)
    {
      my $subtree = _site_tree($file,
                               $uri_dir . $file_name,
                               %tree_vars,
                               LEVEL   => $level + 1,
                               PARENT  => \@pagetree,
                              );
      if($subtree) {
        push @pagetree, $subtree;
        $dirhash{$subtree->{URI}} = $subtree;
        %pagehash = ( %pagehash, %{$subtree->{PAGEHASH}} );
      }
      next;
    }

    my $file_ext = '';
    my $name = $file_name;
    $file_ext = $1 if($name =~ s/\.([^.]+)$//);  # remove file extension

    my $src_type = '';
    my $target_type;

    if(grep(/^$file_ext$/, @raw_copy))
    {
      TRACE "Matched type=$file_ext in dir_vars{RAW_COPY}: $file";
      $src_type = 'RAW';
      $target_type = $file_ext;
    }
    else
    {
      foreach my $key (keys %doctype) {
        my $match = $doctype{$key}->{match} || '\.' . $key . '$';
        $src_type = $key if($file_name =~ m/$match/);
        if($src_type)
        {
          $target_type = $doctype{$key}->{target_type} || $default_target_type;
          TRACE "Matched '$match' for doctype{$key}: $file";
          last;
        }
      }
    }

    unless($src_type && $target_type)
    {
      TRACE "No match, ignoring file: $file";
      next;
    }

    DEBUG "Source File \[$src_type\]: $file"; INDENT 1;

    # get file stats
    my @stat = stat $file;

    # sort menu by filename as default
    my $index;
    if ($name =~ s/^(\d*)-//) {
      $index = $1;
      DEBUG "File index prefix found: $index";
    }

    # set date
    my $time_format = $tree_vars{TIME_FORMAT} || $default_time_format;
    my $mtime = time2str($time_format, $stat[9]);
    my $build_date = time2str($time_format, $tree_vars{BUILD_TIME});

    # page vars default to tree_vars
    my %page = ( NAME        => $name,
                 TARGET_TYPE => $target_type,
                 URI_DIR     => $uri_dir,
                 MTIME       => $mtime,
                 BUILD_DATE  => $build_date,
                 %tree_vars,
                );

    # page vars file supersede the tree vars
    %page = read_vars(file => "$file.vars",
                      vars => \%page);
    %page = read_vars(file => "$vars_overlay.$name.vars",
                      vars => \%page) if($vars_overlay);

    # page nested vars file supersede the page vars
    if(exists($doctype{$src_type}) && $doctype{$src_type}->{nested_vars})
    {
      %page = read_vars(file => $file,
                        vars => \%page,
                        nested => 1,
                       );
    }

    if($page{SKIP}) {
      DEBUG "Found page_vars{SKIP}, skipping file: $file"; INDENT -1;
      next;
    }

    my $uri_unprefixed = set_uri(\%page);
    my $target_file = undef;
    $target_file = $page{TARGET_DIR} . $uri_unprefixed if($page{TARGET_DIR});


    my $target_mtime_epoch = undef;
    if($page{TARGET_MTIME}) {
      my $time = Time::Piece->strptime($page{TARGET_MTIME}, "%Y-%m-%d %H:%M:%S");
      $target_mtime_epoch = $time->epoch;
    }

    %page = (INDEX       => $index || $uri_unprefixed,  # default index
             %page,
             SRC_FILE    => $file,
             SRC_TYPE    => $src_type,
             TARGET_FILE => $target_file,
             TARGET_MTIME_EPOCH => $target_mtime_epoch,
             LEVEL       => $level,
             IS_DIR      => 0,

             SRC_FILE_UID   => $stat[4],
             SRC_FILE_GID   => $stat[5],
             SRC_FILE_SIZE  => $stat[7],
             SRC_FILE_ATIME => $stat[8],
             SRC_FILE_MTIME => $stat[9],
             SRC_FILE_CTIME => $stat[10],
            );

    push @pagetree, \%page;

    # add page to pagehash
    if(exists($pagehash{$page{URI}}))
    {
      WARN "Duplicate URI=$page{URI}"; INDENT 1;
      WARN "Keeping Page: " . $pagehash{$page{URI}}->{SRC_FILE}; INDENT 1;
      DEBUG dump_vars(\%page); INDENT  -1;
      WARN "Ignoring Page: " . $page{SRC_FILE}; INDENT 1;
      DEBUG dump_vars($pagehash{$page{URI}}); INDENT -2;
    }
    $pagehash{$page{URI}} = \%page;

    TRACE "Page vars:" ; INDENT 1;
    TRACE dump_vars(\%page); INDENT -1;
    INDENT -1;
  }

  # sort pages (defeault: string sort by INDEX)
  my $sort_key = $dir_vars{SORT_KEY} || 'INDEX';
  my $sort_strategy = $dir_vars{SORT_STRATEGY} || 'sortkey-only';
  @pagetree = sort { ($sort_strategy eq 'dir-first' ? ($b->{IS_DIR} <=> $a->{IS_DIR}) : 0) ||
                     ($sort_strategy eq 'dir-last'  ? ($a->{IS_DIR} <=> $b->{IS_DIR}) : 0) ||
                     ($a->{$sort_key} cmp $b->{$sort_key}) } @pagetree;

  # set PAGE_PREV / PAGE_NEXT
  my $prev = undef;
  foreach my $p (@pagetree) {
    next if($p->{IS_DIR});
    if($prev) {
      $prev->{PAGE_NEXT} = $p;
      $p->{PAGE_PREV} = $prev;
    }
    $prev = $p;
  }

  # set default index page to first page (used by the menu)
  unless(defined($dir_vars{INDEX_PAGE}))
  {
    foreach my $p (@pagetree) {
      next if($p->{IS_DIR});
      $dir_vars{INDEX_PAGE} = $p->{URI};
      DEBUG "Setting INDEX_PAGE=$p->{URI} for directory: $dir_vars{URI}";
      last;
    }
    WARN "No index page found for directory: $dir_vars{URI}" unless(defined($dir_vars{INDEX_PAGE}));
  }

  return \%dir_vars;
}


sub site_tree
{
  my $self = shift;
  return $self->{root} if $self->{root};

  INFO "Parsing site structure: $self->{vars}->{BASEDIR}"; INDENT 1;

  my $basedir = $self->{vars}->{BASEDIR} || die("No BASEDIR specified");
  $self->{root} = _site_tree($basedir, "", %{$self->{vars}});

  INDENT -1;

  return $self->{root};
}


sub refs
{
  my $self = shift;
  return $self->{refs} if(exists($self->{refs}));
  $self->{refs} = {};
  DEBUG "Processing references:"; INDENT 1;
  foreach my $page (values %{$self->site_tree()->{PAGEHASH}})
  {
    next unless($page->{REF});
    foreach my $r (split /[,;]/, $page->{REF}) {
      $r =~ s/^\s+//;
      $r =~ s/\s+$//;
      $r = lc $r;
      WARN "Duplicate reference \"$r\"" if(exists($self->{refs}->{$r}));
      $self->{refs}->{$r} = $page->{URI};
      TRACE "Adding reference \"$r\": $self->{refs}->{$r}";
    }
  }
  INDENT -1;
  return $self->{refs};
}


sub _traverse
{
  my $args = shift;
  my $tree = shift;
  my $match = $args->{match};
  my $depth = $args->{depth};
  my $collapse = $args->{collapse};
  my $page_current = $args->{page_current};
  my $callback = $args->{CALLBACK} || die("traverse: argument missing: CALLBACK");
  my $ret = '';

  foreach my $p (@$tree) {
    next if($depth && ($p->{LEVEL} > $depth));

    my $skip = 0;
    if($match)
    {
      # skip pages which are not matching ALL criteria
      foreach my $key (keys %{$args->{match}}) {
        unless(exists($p->{$key}) && ($p->{$key} =~ m/$args->{match}->{$key}/)) {
          $skip = 1;
          last;
        }
      }
    }
    $ret .= &$callback($p, $args) unless($skip);

    if($p->{IS_DIR})
    {
      # p is directory, recurse into it
      if((not $collapse) || $p->{PAGEHASH}->{$page_current->{URI}}) {
        $ret .= _traverse($args, $p->{TREE});
      } else {
        DEBUG "Collapsing $p->{URI}";
      }
    }
  }
  return $ret;
}


sub traverse
{
  my $args = shift;
  my $root = $args->{ROOT};
  die("traverse: missing/invalid argument \"ROOT\"") unless(ref($root) eq 'HASH');
  die("traverse: argument \"ROOT\" must be a directory") unless($root->{TREE});

  my $last_level = $root->{LEVEL} - 1;
  $args->{init_level} = $root->{LEVEL};
  $args->{last_level} = \$last_level;

  DEBUG "Traverse depth=$args->{depth}" if($args->{depth});
  DEBUG "Traverse collapse=$args->{collapse}" if($args->{collapse});

  return _traverse($args, $root->{TREE});
}


sub sitemap
{
  my $self = shift;
  my $root = shift || $self->site_tree();

  return traverse(
    { ROOT => $root,
      CALLBACK =>
      sub {
        my $page = shift;
        my $ret;
        $ret .= '  ' x $page->{LEVEL};
        $ret .= $page->{IS_DIR} ? '* ' : '- ';
        $ret .= $page->{URI} . "\n";
        return $ret;
      },
    } );
}


sub dump_vars
{
  my $page = shift;
  my $dump = '';
  my @strip = qw( TEMPLATE_INPUT  SRC_TEXT );
  foreach my $key (sort keys %$page) {
    if(grep(/^$key$/, @strip)) {
      $dump .= "$key=***stripped***\n";
    } else {
      $dump .= "$key=" . (defined($page->{$key}) && $page->{$key}) . "\n";
    }
  }
  return $dump;
}


sub page
{
  my $self = shift;
  my $uri = shift;
  my $data = shift;  # optional
  my $root = $self->site_tree();
  my $page = $root->{PAGEHASH}->{$uri};

  unless($page) {
    ERROR "Invalid URI: $uri";
    return undef;
  }
  return $self->process_page($page, $data);
}


sub page_vars
{
  my $self = shift;
  my $uri = shift;
  my $root = $self->site_tree();
  return $root unless($uri);

  unless(exists $root->{PAGEHASH}->{$uri}) {
    ERROR "Invalid URI: $uri";
    return undef;
  }
  return $root->{PAGEHASH}->{$uri};
}


sub create
{
  my $self = shift;
  my @uri_filter = @_;
  my $root = $self->site_tree();
  my @dir_created;

  INFO "Creating output files:"; INDENT 1;
  foreach my $page (values %{$root->{PAGEHASH}}) {
    next if(@uri_filter && !grep(/^$page->{URI}$/, @uri_filter));
    my $html = $self->process_page($page);
    my $dfile = $page->{TARGET_FILE};
    die "unknown destination file (maybe you forgot to set \"TARGET_DIR\" in \"$tree_vars_filename\"?)" unless($dfile);

    # create directory
    my (undef, $dir, undef) = splitpath($page->{TARGET_FILE});
    unless (grep(/^$dir$/, @dir_created)) {
      DEBUG "Creating directory: $dir";
      mkpath($dir);
      push(@dir_created, $dir);
    }

    # write page to file
    DEBUG "Writing file: $dfile";
    if(open(OUTFILE, ">$dfile")) {
      print OUTFILE $html;
      close(OUTFILE);

      # update mtime if TARGET_MTIME is set
      if($page->{TARGET_MTIME_EPOCH}) {
        DEBUG "Setting file ATIME=MTIME='$page->{TARGET_MTIME}' ($page->{TARGET_MTIME_EPOCH})";
        utime($page->{TARGET_MTIME_EPOCH}, $page->{TARGET_MTIME_EPOCH}, $dfile);
      }
    } else {
      ERROR "Failed to write file \"$dfile\": $!";
    }
  }

  INDENT -1;
  return 1;
}


sub command
{
  my $self = shift;
  my $cmd_key = shift;
  my $root = $self->site_tree();

  $cmd_key = 'CMD_' . uc($cmd_key);
  my $cmd = $root->{$cmd_key};

  unless($cmd) {
    return (-1, ERROR "Variable \"$cmd_key\" is not defined in vars.", "");
  }

  INFO "Executing: '$cmd'"; INDENT 1;
  my $ret = `$cmd 2>&1`;
  INFO "$ret";

  my $msg;
  if($?) {
    $msg = ERROR "Command execution failed ($?)";
  } else {
    $msg = INFO "Command execution successful";
  }
  INDENT -1;
  return ($?, $msg, $ret);
}


1;
