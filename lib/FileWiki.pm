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

The full documentation is available at L<http://www.digint.ch/filewiki>.

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


package FileWiki;

use strict;
use warnings;

use FileWiki::Logger;

use Date::Format qw(time2str);
use Time::Piece;
use File::Path qw(mkpath);
use File::Spec::Functions qw(splitpath);

use Template;

our $VERSION = "0.31-dev";

# Defaults
our $dir_vars_filename = 'dir.vars';
our $tree_vars_filename = 'tree.vars';
our $default_time_format = '%C';

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

  DEBUG "FileWiki module v$VERSION";
  TRACE "Initial vars:"; INDENT 1;
  TRACE dump_vars($self->{vars}); INDENT -1;

  return $self;
}

sub eval_module
{
  my $module = shift;
  my $msg = shift || "";
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

  my $fh;
  open($fh, "<$file") or die "Failed to open file \"$file\": $!";

  if($args{nested}) {
    my $found = 0;
    while (<$fh>) {
      if( /^(.?)[<\[]filewiki_vars[>\]]/ ) {
        $nested_remove_char = $1;
        $found = 1;
        last;
      }
    }

    unless($found) {
      DEBUG "No nested vars found"; INDENT -1;
      close $fh;
      return %vars;
    }
  }

  while (<$fh>) {
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

    # include vars
    if($key eq "INCLUDE_VARS") {
      DEBUG "INCLUDE_VARS: including $val";
      %vars = read_vars(file => $val, vars => \%vars);
      next;
    }

    $vars{$key} = $val;
    TRACE "$key=$val";
  }
  INDENT -1;
  close($fh);
  return %vars;
}


sub expand_match_vars
{
  my $vars = shift;
  my $prefix = $vars->{IS_DIR} ? "DIR_MATCH_" : "MATCH_";

  foreach my $key (keys (%$vars)) {
    next unless($key =~ m/^$prefix(.+)/);

    my $key_set = $1;
    if (defined($vars->{$key_set})) {
      DEBUG "Resulting key '$key_set' is already defined, ignoring '$key'";
      next;
    }

    my $val = $vars->{$key};
    if ($val =~ m/^(\w+):(.*)/) {
      my ($match_key, $match_expr) = ($1, $2);
      unless($match_key && $match_expr) {
        ERROR "Bad match variable. Expected \"<key>:<regexp>\", got \"$key=$val\".";
        next;
      }
      TRACE "Expanding $key";

      if (defined($vars->{$match_key})) {
        if ($vars->{$match_key} =~ m/$match_expr/) {
          if ($1) {
            $vars->{$key_set} = $1;
            DEBUG "Matched $match_key, expanding $key_set=$1";
          } else {
            WARN "Bad match expression (no result): $match_expr";
          }
        }
      } else {
        DEBUG "Key '$match_key' not found while expanding '$key'";
      }
    }
  }
}


sub sanitize_vars
{
  my $vars = shift;
  foreach my $key (keys (%$vars)) {
    next unless($key =~ m/^SANITIZE_(.+)/);
    my $key_set = $1;
    next unless($vars->{$key});  # value is false
    unless(defined($vars->{$key_set})) {
      TRACE "Resulting key '$key_set' is not defined, ignoring '$key'";
      next;
    }
    my $val = $vars->{$key_set};
    if($val =~ s/_/ /g) {
      $vars->{$key_set} = $val;
      DEBUG "Sanitized key: $key_set=\"$val\"";
    }
  }
}


sub process_page
{
  my $self = shift;
  my $page = shift;
  my $data = shift || "";

  if($page->{HANDLER})
  {
    DEBUG "Processing page: $page->{URI}"; INDENT 1;

    $page->{SRC_TEXT} = $data if($data);

    $data = $page->{HANDLER}->process_page($page, $self);

    INDENT -1;
  }

  return $data;
}


sub set_uri
{
  my $page = shift;

  # sanitize
  $page->{URI_DIR} =~ s/\/+$//;
  $page->{URI_DIR} .= '/';
  $page->{URI_PREFIX} =~ s/\/+$//;
  $page->{URI_PREFIX} =~ s/^([^\/])/\/$1/;

  my $uri = $page->{URI_DIR};
  $uri .= $page->{HANDLER}->get_uri_filename($page) if($page->{HANDLER});
  $uri = lc($uri) if($page->{URI_TRANSFORM_LC});

  $page->{URI} = $page->{URI_PREFIX} . $uri;
  return $uri;
}

sub load_plugins
{
  my $page = shift;

  my @plugins = split(/[,;]\s*/, $page->{PLUGINS});
  my @ret;

  foreach (@plugins) {
    my $plugin = "FileWiki::Plugin::$_";

    TRACE "Loading plugin '$plugin'";
    unless(eval "require $plugin;") {
      ERROR "Failed to load FileWiki plugin \"$plugin\": $page->{SRC_FILE}";
      DEBUG "$@";
      next;
    }
    push @ret, $plugin;
  }
  return @ret;
}


sub get_handler
{
  my $page = shift;

  foreach my $plugin (load_plugins($page)) {
    my $handler = $plugin->new($page);
    if($handler) {
      TRACE "Using plugin: $handler->{name}";
      return $handler;
      last;
    }
  }
  return undef;
}


sub _site_tree
{
  my ($src_dir, $uri_dir, %tree_vars) = @_;
  my $level = $tree_vars{LEVEL} || 1;
  my @pagetree;
  my %pagehash;
  my %dirhash;
  my %dir_vars;

  DEBUG "Entering directory: $src_dir";

  my $uri_dirname = $uri_dir;
  $uri_dirname =~ s/(.*\/)//;   # greedy
  my $uri_basedir = $1 || "";

  %dir_vars = ( INDEX   => $uri_dirname,
                NAME    => $uri_dirname,
               );

  # change uri_dir and uri_dirname according to NAME_MATCH
  if($tree_vars{NAME_MATCH}) {
    if($dir_vars{NAME} =~ m/$tree_vars{NAME_MATCH}/) {
      $dir_vars{NAME} = $1;
      DEBUG "Got match on NAME_MATCH: setting NAME=\"$dir_vars{NAME}\"";
    }
  }

  # get overlay prefix for INCLUDE's
  my $vars_overlay = $tree_vars{VARS_OVERLAY}->{$src_dir};

  # provide DIR in tree_vars
  %tree_vars = ( %tree_vars,
                 DIR => \%dir_vars );

  # read the tree vars (defaults to upper level tree vars)
  %tree_vars = read_vars(file => "$src_dir/$tree_vars_filename",
                         vars => \%tree_vars);
  %tree_vars = read_vars(file => "$vars_overlay.$tree_vars_filename",
                         vars => \%tree_vars) if($vars_overlay);

  # read the dir vars (no propagation)
  %dir_vars = ( NAME => "ROOT",   # default
                %tree_vars,
                %dir_vars,
                URI_DIR => $uri_basedir . $dir_vars{NAME},
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
                SRC_FILE => $src_dir . '/',
                IS_DIR   => 1,
               );

  # set the handler and vars needed for a directory index page
  my $dir_uri_unprefixed = set_uri(\%dir_vars);

  expand_match_vars(\%dir_vars);
  sanitize_vars(\%dir_vars);

  TRACE "Dir vars:" ; INDENT 1;
  TRACE dump_vars(\%dir_vars);
  INDENT -1;

  if($dir_vars{SKIP})
  {
    INFO "$src_dir/  ***SKIP***";
    return undef;
  }
  INFO "$src_dir/";

  $tree_vars{ROOT} = \%dir_vars unless($tree_vars{ROOT});

  my @files;
  opendir(my $dh, $src_dir) || die("uups, failed to open directory: $src_dir");
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
    my @includes = split(/:/, $dir_vars{INCLUDE});
    foreach my $include (@includes) {
      my $overlay = $1 if($include =~ s/\[(\w+)\]//);
      $include =~ s/\/*$//;

      $tree_vars{VARS_OVERLAY}->{$include} = "$src_dir/$overlay" if($overlay);
      push @files, $include;
    }
  }


  foreach my $file (@files)
  {
    $file =~ m/\/([^\/]+)$/;
    my $file_name = $1 || die("uups, '$file' is a directory but does not end with '/*'");

    # add overlay for the file/dir if the current directory has an overlay
    $tree_vars{VARS_OVERLAY}->{$file} = $vars_overlay . '_' . $file_name if($vars_overlay);

    if(-d $file)
    {
      my $subtree = _site_tree($file,
                               $dir_vars{URI_DIR} . $file_name,
                               %tree_vars,
                               LEVEL   => $level + 1,
                               PARENT_DIR  => \%dir_vars,
                              );
      if($subtree) {
        push @pagetree, $subtree;
        $dirhash{$subtree->{URI}} = $subtree;
        %pagehash = ( %pagehash, %{$subtree->{PAGEHASH}} );
      }
      next;
    }

    DEBUG "Source File: $file"; INDENT 1;

    my $file_ext = '';
    my $name = $file_name;
    $file_ext = $1 if($name =~ s/\.([^.]+)$//);  # remove file extension

    # get file stats
    my @stat = stat $file;

    # set date
    my $time_format = $tree_vars{TIME_FORMAT} || $default_time_format;
    my $mtime = time2str($time_format, $stat[9]);
    my $build_date = time2str($time_format, $tree_vars{BUILD_TIME});

    # page vars default to tree_vars
    my %page = ( INDEX       => $name,
                 NAME        => $name,
                 URI_DIR     => $dir_vars{URI_DIR},
                 MTIME       => $mtime,
                 BUILD_DATE  => $build_date,
                 %tree_vars,
                );

    # change NAME according to NAME_MATCH
    if($tree_vars{NAME_MATCH}) {
      if($page{NAME} =~ m/$tree_vars{NAME_MATCH}/) {
        $page{NAME} = $1;
        DEBUG "Got match on NAME_MATCH: setting NAME to \"$page{NAME}\"";
      }
    }

    # page vars file supersede the tree vars
    %page = read_vars(file => "$file.vars",
                      vars => \%page);
    %page = read_vars(file => "$tree_vars{VARS_OVERLAY}->{$file}.vars",
                      vars => \%page) if($tree_vars{VARS_OVERLAY}->{$file});


    # attach plugin to the page
    $page{SRC_FILE} = $file;
    my $handler = get_handler(\%page);
    unless($handler) {
      TRACE "No match, ignoring file: $file"; INDENT -1;
      next;
    }
    $page{HANDLER} = $handler;

    # page nested vars file supersede the page vars
    if($handler->{read_nested_vars})
    {
      %page = read_vars(file => $file,
                        vars => \%page,
                        nested => 1,
                       );
    }

    if($page{SKIP}) {
      INFO "$file  ***SKIP***"; INDENT -1;
      next;
    }
    INFO "$file";

    my $uri_unprefixed = set_uri(\%page);
    die "OUTPUT_DIR is not set, refusing to continue" unless($page{OUTPUT_DIR});
    my $target_file = $page{OUTPUT_DIR} . $uri_unprefixed;
    my (undef, $target_dir, undef) = splitpath($target_file);

    my $target_mtime_epoch = undef;
    if($page{TARGET_MTIME}) {
      my $time = Time::Piece->strptime($page{TARGET_MTIME}, "%Y-%m-%d %H:%M:%S");
      $target_mtime_epoch = $time->epoch;
    }

    %page = (INDEX       => $page{NAME},  # default index
             %page,
             SRC_FILE    => $file,
             TARGET_FILE => $target_file,  # full path
             TARGET_DIR  => $target_dir,
             TARGET_MTIME_EPOCH => $target_mtime_epoch,
             LEVEL       => $level,
             IS_DIR      => 0,

             SRC_FILE_NAME  => $file_name,
             SRC_FILE_UID   => $stat[4],
             SRC_FILE_GID   => $stat[5],
             SRC_FILE_SIZE  => $stat[7],
             SRC_FILE_ATIME => $stat[8],
             SRC_FILE_MTIME => $stat[9],
             SRC_FILE_CTIME => $stat[10],
            );

    # set a link to self, useful in templates
    $page{VARS} = \%page;

    # call the handler hook
    $handler->update_vars(\%page);

    expand_match_vars(\%page);
    sanitize_vars(\%page);

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
  my $sort_order = $dir_vars{SORT_ORDER} || 'asc';
  @pagetree = sort { ($sort_strategy eq 'dir-first' ? ($b->{IS_DIR} <=> $a->{IS_DIR}) : 0) ||
                     ($sort_strategy eq 'dir-last'  ? ($a->{IS_DIR} <=> $b->{IS_DIR}) : 0) ||
                     ($sort_order eq 'asc'  ?
                      (($a->{$sort_key} || $a->{INDEX}) cmp ($b->{$sort_key} || $b->{INDEX})) :
                      (($b->{$sort_key} || $b->{INDEX}) cmp ($a->{$sort_key} || $a->{INDEX})))
                   } @pagetree;

  # set PAGE_PREV / PAGE_NEXT
  my $prev = undef;
  foreach (@pagetree) {
    next if($_->{IS_DIR});
    next if($_->{SKIP_PREVNEXT});
    if($prev) {
      $prev->{PAGE_NEXT} = $_;
      $_->{PAGE_PREV} = $prev;
    }
    $prev = $_;
  }

  # honor MAKE_INDEX_PAGE (set index page to the first occurence)
  unless(defined($dir_vars{INDEX_PAGE}))
  {
    foreach (@pagetree) {
      next unless($_->{MAKE_INDEX_PAGE});
      $dir_vars{INDEX_PAGE} = $_;
      DEBUG "Found page_vars{MAKE_INDEX_PAGE}, setting INDEX_PAGE=$_->{URI} for directory: $dir_vars{URI}";
      last;
    }
  }

  # set default index page to first page (used by the menu)
  unless(defined($dir_vars{INDEX_PAGE}))
  {
    foreach (@pagetree) {
      next if($_->{IS_DIR});
      $dir_vars{INDEX_PAGE} = $_;
      DEBUG "Setting INDEX_PAGE=$_->{URI} for directory: $dir_vars{URI}";
      last;
    }
    DEBUG "No index page found for directory: $dir_vars{URI}" unless(defined($dir_vars{INDEX_PAGE}));
  }

  return \%dir_vars;
}


sub site_tree
{
  my $self = shift;
  return $self->{root} if $self->{root};

  INFO "Parsing site structure: $self->{vars}->{BASEDIR}"; INDENT 1;
  my $start_time = time;

  my $basedir = $self->{vars}->{BASEDIR} || die("No BASEDIR specified");
  $self->{root} = _site_tree($basedir, "", %{$self->{vars}});

  INFO "Time elapsed: " . (time - $start_time) . "s";

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
  my %flags = @_;
  my $match = $args->{match};
  my $last_level = $args->{last_level};
  my $collapse = $args->{collapse};
  my $page_current = $args->{page_current};
  my $callback = $args->{CALLBACK} || die("traverse: argument missing: CALLBACK");
  my $ret = '';

  foreach my $p (@$tree) {
    next if($last_level && ($p->{LEVEL} > $last_level));

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
    $ret .= &$callback($p, $args, %flags) unless($skip);

    if($p->{IS_DIR})
    {
      # p is directory, recurse into it
      my $collapsed = not ($page_current && $p->{PAGEHASH}->{$page_current->{URI}}); # current page not present in pagehash
      if($collapse && $collapsed) {
        DEBUG "Collapsing $p->{URI}";
      } else {
        $ret .= _traverse($args, $p->{TREE}, %flags, collapse => $collapsed);
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

  my $prev_level = $root->{LEVEL} - 1;
  $args->{init_level} = $root->{LEVEL};
  $args->{prev_level} = \$prev_level;
  $args->{last_level} = $root->{LEVEL} + $args->{depth} if(defined($args->{depth}));

  DEBUG "Traverse depth=$args->{depth}" if($args->{depth});
  DEBUG "Traverse init_level=$args->{init_level}, last_level=$args->{last_level}" if($args->{last_level});
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
  my $start_time = time;
  my $self = shift;
  my @uri_filter = @_;
  my $root = $self->site_tree();
  my @dir_created;

  INFO "Creating output files:"; INDENT 1;

  my $ret = traverse(
    { ROOT => $root,
      CALLBACK =>
      sub {
        my $page = shift;
        return "" if(@uri_filter && !grep(/^$page->{URI}$/, @uri_filter));
        return "" unless($page->{HANDLER});
        my $dfile = $page->{TARGET_FILE};
        die "unknown destination file (maybe you forgot to set \"OUTPUT_DIR\" in \"$tree_vars_filename\"?)" unless($dfile);

        # create directory
        my $dir = $page->{TARGET_DIR};
        unless (grep(/^$dir$/, @dir_created)) {
          DEBUG "Creating directory: $dir";
          mkpath($dir);
          push(@dir_created, $dir);
        }

        # process page
        my $html = $self->process_page($page);

        # write page to file
        INFO ">>> $dfile";
        if (open(OUTFILE, ">$dfile")) {
          print OUTFILE $html;
          close(OUTFILE);

          # update mtime if TARGET_MTIME is set
          if ($page->{TARGET_MTIME_EPOCH}) {
            DEBUG "Setting file ATIME=MTIME='$page->{TARGET_MTIME}' ($page->{TARGET_MTIME_EPOCH})";
            utime($page->{TARGET_MTIME_EPOCH}, $page->{TARGET_MTIME_EPOCH}, $dfile);
          }
        } else {
          ERROR "Failed to write file \"$dfile\": $!";
        }
        return $dfile . "\n";
      },
    } );

  INFO "Time elapsed: " . (time - $start_time) . "s";

  INDENT -1;
  return $ret;
}


sub command
{
  my $start_time = time;
  my $self = shift;
  my $cmd_key = shift;
  my $root = $self->site_tree();

  $cmd_key = 'CMD_' . uc($cmd_key);
  my $cmd = $root->{$cmd_key};

  unless($cmd) {
    return (-1, ERROR("Variable \"$cmd_key\" is not defined in vars."), "");
  }

  INFO "Executing: '$cmd'"; INDENT 1;
  my $ret = `$cmd 2>&1`;
  INFO "$ret";

  my $msg;
  if($?) {
    $msg = ERROR "Command execution failed ($?)";
  }

  INFO "Time elapsed: " . (time - $start_time) . "s";

  INDENT -1;
  return ($?, $msg, $ret);
}


1;
