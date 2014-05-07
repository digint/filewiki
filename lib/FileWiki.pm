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


package FileWiki;

use strict;
use warnings;

use FileWiki::Logger;

use Date::Format qw(time2str);
use Time::Piece;
use File::Path qw(mkpath);
use File::Spec::Functions qw(splitpath);

our $VERSION = "0.40";

# Defaults
our $default_time_format = '%C';

our $dir_vars_filename = 'dir.vars';
our $tree_vars_filename = 'tree.vars';
our $var_decl = qr/_*[A-Za-z][A-Za-z_0-9]*/;


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


sub expand_var
{
  # expand variable in form 'VAR' or 'VAR0|VAR1|...VARn'
  my ($vars, $expr, %args) = @_;
  my $debug_location = $args{debug_file} ? " in $args{debug_file} line $." : " for $vars->{SRC_FILE}";
  my $value = undef;

  foreach my $key (split(/\|/, $expr))
  {
    next unless($key);
    unless($key =~ /^$var_decl$/) {
      ERROR "Illegal variable name \"$key\" in expansion \"$expr\"$debug_location\n";
      return undef;
    }

    if(defined($vars->{$key}) && ($vars->{$key} ne "")) {
      $value = $vars->{$key};
      last;
    }
    elsif(defined($vars->{$key})) {
      # return an empty string if one of the vars was defined
      $value = "";
    }
  }

  if(defined($value)) {
    TRACE "Expanding variable expression: \"$expr\" -> \"$value\"";
  } else {
    if($args{enable_late_expansion}) {
      DEBUG "Failed to expand variable \"$expr\"$debug_location\n";
    } else {
      WARN "Failed to expand variable \"$expr\"$debug_location\n";
    }
  }

  # $value ||= "<undef>";  # nice for debugging
  return $value;
}


sub expand_expr
{
  # expand expressions in form 'KEY' or 'KEY:REGEXP'
  my ($vars, $expr, %args) = @_;
  my $debug_location = $args{debug_file} ? " in $args{debug_file} line $." : " for $vars->{SRC_FILE}";
  my $saved_expr = $expr;
  my $expanded;

  $expr =~ s/^\$//;  # remove '$'

  if($expr =~ s/^\(\((.*)\)\)$/$1/)   # remove '((...))'
  {
    # recursively dive into '$(( ... ))' constructs

    return $saved_expr unless($args{enable_late_expansion});

    $expr =~ s/^\s*//;
    $expr =~ s/\s*$//;

    TRACE "Expanding logical expression: \"$saved_expr\""; INDENT 1;

    # handle '$(( [!]CONDITION: ...))
    my $skip = 0;
    if($expr =~ s/^(.*?):\s*//) {
      my $cond_expr = $1;
      my $inverted = 0;
      $inverted = 1 if($cond_expr =~ s/^!\s*//);
      $skip = expand_var($vars, $cond_expr, %args) ? 0 : 1;
      $skip = !$skip if($inverted);
      TRACE "Conditional expression resolves to false, skipping" if($skip);
    }

    unless($skip)
    {
      # handle '$(( A || B ))' (very simple matching, sorry...)
      foreach (split(/ \|\| /, $expr)) {
        my $ret = expand_expr($vars, $_, %args);
        if($ret) {
          $expanded = $ret;
          last;
        }
      }
    }
  }
  else
  {
    $expr =~ s/^{(.*)}$/$1/;       # remove '{}'
    if($expr =~ s/^{(.*)}$/$1/) {  # remove '{}' second time (late expansion)
      return $saved_expr unless($args{enable_late_expansion});
    }

    TRACE "Expanding expression: \"$saved_expr\""; INDENT 1;

    my $var_expr = $expr;
    my $global = 0;
    my $regexp_expr = undef;
    if($expr =~ /^(.*?)\/\/(.*)/) {  # 'var_expr//regexp'
      ($var_expr, $regexp_expr) = ($1, $2);
      $global = 1;
    }
    elsif($expr =~ /^(.*?)\/(.*)/) {  # 'var_expr/regexp'
      ($var_expr, $regexp_expr) = ($1, $2);
    }

    # expand variable
    $expanded = expand_var($vars, $var_expr, %args);

    # apply regular expression
    if(defined($expanded) && defined($regexp_expr))
    {
      if($regexp_expr =~ /^(.*?[^\\])\/(.*)/) {  # 'match/replace'
        my ($match, $replace) = ($1, "\"$2\"");  # quote $2, because of eval() below
        TRACE "Applying regular expression: match=\"$match\", replace=$replace";

        # use double eval (security risk here!)

        my $success;
        if($global) {
          $success = ($expanded =~ s/$match/$replace/gee);
        } else {
          $success = ($expanded =~ s/$match/$replace/ee);
        }
        DEBUG "Regular expression failed: match=\"$match\", replace=$replace on string \"$expanded\"$debug_location\n" unless($success);
      }
    }
  }
  $expanded //= "";  # soft fail
  TRACE "result: \"$saved_expr\" -> \"$expanded\""; INDENT -1;
  return $expanded;
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
    my ($modifier, $key, $val) = /^\s*(\+?)($var_decl)[\s=]+(.*?)\s*$/;

    unless($key && defined($modifier) && defined($val)) {
      WARN "Ambiguous variable declaration: $file line $.";
      next;
    }

    # store raw value before expanding
    $vars{VARS_PRE_EXPAND} = { } unless(exists($vars{VARS_PRE_EXPAND}));
    $vars{VARS_PRE_EXPAND}->{$key} = $val unless($modifier eq '+');

    if($val =~ /^\$$var_decl$/) {
      # directly assignment (important to assign references)
      $vars{$key} = expand_expr(\%vars, $val, debug_file => $file);
      next;
    }

    # remove quotes
    $val =~ s/^"//;
    $val =~ s/"$//;

    # expand variables
    $val =~ s/(\${[^{].*?[^}]})/expand_expr(\%vars, $1, debug_file => $file)/eg;
    $val =~ s/(\$$var_decl)/expand_expr(\%vars, $1, debug_file => $file)/eg;

    # include vars
    if($key eq "INCLUDE_VARS") {
      DEBUG "INCLUDE_VARS: including $val";
      unless(-r "$val") {
        WARN "Failed to include vars from file '$val': File not found";
        next;
      }
      %vars = read_vars(file => $val, vars => \%vars);
      next;
    }

    if($modifier eq '+') {
      $vars{$key} = [] unless(ref($vars{$key}) eq 'ARRAY');
      push(@{$vars{$key}}, $val);
      TRACE "+$key=$val";
    }
    else {
      $vars{$key} = $val;
      TRACE "$key=$val";
    }
  }
  INDENT -1;
  close($fh);
  return %vars;
}


sub expand_late_vars
{
  my $vars = shift;
  DEBUG "Expanding late-expand vars"; INDENT 1;
  foreach my $key (keys %$vars)
  {
    # sanity check
    next unless(defined($vars->{$key}));
    next if(ref($vars->{$key}));
    my $warn_system_variable = 0;

    # expand late-expand logical expressions of form: $((myexpr))
    if($vars->{$key} =~ s/(\$\(\(.*?\)\))/expand_expr($vars, $1, enable_late_expansion => 1)/eg) {
      $warn_system_variable = 1;
    }

    # expand late-expand values of form: ${{myvar}}
    if($vars->{$key} =~ s/(\${{.*?}})/expand_expr($vars, $1, enable_late_expansion => 1)/eg) {
      $warn_system_variable = 1;
    }

    if($warn_system_variable && (uc($key) eq $key) && ($key ne "REF") && ($key ne "TARGET_MTIME")) {
      WARN "Late expansion to a system or plugin variable is discouraged: key='$key'";
    }

  }
  INDENT -1;
  return $vars;
}


sub eval_vars
{
  # note: big fat security hole here!
  my ($vars, $eval_aref, %args) = @_;
  return $vars unless(ref($eval_aref) eq 'ARRAY');

  DEBUG "Evaluating EVAL expressions" . ($args{early_eval} ? " (early eval)" : ""); INDENT 1;
  foreach my $ele (@$eval_aref)
  {
    # eval expressions in form '[!]KEY: EXPR'
    $ele =~ /^(!?)($var_decl)\s*:\s*(.*)/;
    my ($modifier, $key, $expr) = ($1, $2, $3);
    if($modifier eq '!') {
      next unless $args{early_eval};
    } else {
      next if $args{early_eval};
    }

    if($key && defined($expr)) {
      DEBUG "Evaluating expression for key=\"$key\": $expr";
      my $saved_val = $vars->{$key};
      {
        local $@;
        no warnings 'all';
        $_ = $vars->{$key};
        eval "$expr";
        if($@) {
          WARN "Error evaluating expression '$expr' for key=\"$key\": $@";
        }
        else {
          $vars->{$key} = $_;
          if($saved_val ne $vars->{$key}) {
            TRACE "  $key: \"$saved_val\" -> \"$vars->{$key}\"";
            if((not $args{early_eval}) && (uc($key) eq $key) && ($key ne "REF") && ($key ne "TARGET_MTIME")) {
              WARN "Setting system or plugin variables using EVAL statements is discouraged: key='$key'";
            }
          }
        }
      }
    }
  }
  INDENT -1;
  return $vars;
}


sub process_page
{
  my $self = shift;
  my $page = shift;
  my $data = shift || "";

  if($page->{HANDLER})
  {
    DEBUG "Processing page: $page->{URI}"; INDENT 1;

    # override SRC_TEXT if data was passed
    $page->{SRC_TEXT} = $data if($data);

    # call the page process handler
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


sub assign_plugins
{
  my $page = shift;

  $page->{PROVIDER} = [];
  foreach my $plugin (load_plugins($page)) {
    my $object = $plugin->new($page);
    if($object) {
      if($object->{vars_provider}) {
        DEBUG "Using vars provider plugin: $object->{name}";
        push(@{$page->{PROVIDER}}, $object);
      }
      if($object->{page_handler}) {
        if($page->{HANDLER}) {
          WARN "Multiple page handler plugins defined for '$page->{SRC_FILE}': using $page->{HANDLER}->{name}, ignoring $object->{name}";
        }
        else {
          DEBUG "Using handler plugin: $object->{name}";
          $page->{HANDLER} = $object;
        }
      }
      if($object->{read_nested_vars}) {
        $page->{VARS_NESTED} = 1;  # triggers reading below
      }
    }
  }
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
  $uri_dirname =~ s/^(.*\/)//;   # greedy
  my $uri_basedir = $1 || "";

  # get overlay prefix for INCLUDE's
  my $vars_overlay = $tree_vars{VARS_OVERLAY}->{$src_dir};

  # provide DIR in tree_vars
  $tree_vars{DIR} = \%dir_vars;

  # read the tree vars (defaults to upper level tree vars)
  %tree_vars = read_vars(file => "$src_dir/$tree_vars_filename",
                         vars => \%tree_vars);
  %tree_vars = read_vars(file => "$vars_overlay.$tree_vars_filename",
                         vars => \%tree_vars) if($vars_overlay);

  # presets for dir_vars
  %dir_vars = ( %tree_vars,
                INDEX   => $uri_dirname,
                NAME    => $uri_dirname,
               );

  # early evaluate for dir_vars
  eval_vars(\%dir_vars, $tree_vars{EVAL}, early_eval => 1);

  # read the dir vars (no propagation)
  %dir_vars = read_vars(file => "$src_dir/$dir_vars_filename",
                        vars => \%dir_vars);
  %dir_vars = read_vars(file => "$vars_overlay.$dir_vars_filename",
                        vars => \%dir_vars) if($vars_overlay);

  %dir_vars = ( URI_DIR => $uri_basedir . $dir_vars{NAME},
                %dir_vars,
                LEVEL    => $level - 1,
                TREE     => \@pagetree,
                PAGEHASH => \%pagehash,
                DIRHASH  => \%dirhash,
                SRC_FILE => $src_dir . '/',
                IS_DIR   => 1,
               );

  # set the handler and vars needed for a directory index page
  my $dir_uri_unprefixed = set_uri(\%dir_vars);

  expand_late_vars(\%dir_vars);
  eval_vars(\%dir_vars, $tree_vars{EVAL});

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
    $tree_vars{TIME_FORMAT} ||= $default_time_format;
    my $mtime = time2str($tree_vars{TIME_FORMAT}, $stat[9]);
    my $build_date = time2str($tree_vars{TIME_FORMAT}, $tree_vars{BUILD_TIME});

    # page vars default to tree_vars
    my %page = ( INDEX       => $name,
                 NAME        => $name,
                 URI_DIR     => $dir_vars{URI_DIR},
                 MTIME       => $mtime,
                 BUILD_DATE  => $build_date,
                 %tree_vars,
                );

    # early evaluate for page
    eval_vars(\%page, $tree_vars{EVAL}, early_eval => 1);

    # page vars file supersede the tree vars
    %page = read_vars(file => "$file.vars",
                      vars => \%page);
    %page = read_vars(file => "$tree_vars{VARS_OVERLAY}->{$file}.vars",
                      vars => \%page) if($tree_vars{VARS_OVERLAY}->{$file});

    # assign plugins to the page
    $page{SRC_FILE} = $file;
    assign_plugins(\%page);
    unless($page{HANDLER}) {
      TRACE "No page handler plugin match, ignoring file: $file"; INDENT -1;
      next;
    }

    # page nested vars file supersede the page vars
    if($page{VARS_NESTED}) {
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

    my $uri_unprefixed = set_uri(\%page);     # sets $page{URI} from handler plugin
    die "OUTPUT_DIR is not set, refusing to continue" unless($page{OUTPUT_DIR});
    my $target_file = $page{OUTPUT_DIR} . $uri_unprefixed;
    my (undef, $target_dir, undef) = splitpath($target_file);

    if($page{TARGET_MTIME}) {
      my $time = Time::Piece->strptime($page{TARGET_MTIME}, "%Y-%m-%d %H:%M:%S");
      $page{TARGET_MTIME_EPOCH} = $time->epoch;
    }

    %page = (%page,
             TARGET_FILE => $target_file,  # full path
             TARGET_DIR  => $target_dir,
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

    # call all vars provider hooks
    foreach my $provider (@{$page{PROVIDER}}) {
      $provider->update_vars(\%page);
    }

    expand_late_vars(\%page);
    eval_vars(\%page, $page{EVAL});

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
    }
    elsif(ref($page->{$key}) eq 'ARRAY') {
      $dump .= "$key=[ " . join(", ", map qq("$_"), @{$page->{$key}}) . " ]\n";
    }
    else {
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
