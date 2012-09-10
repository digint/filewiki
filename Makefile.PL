use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'FileWiki',
  VERSION_FROM  => 'lib/FileWiki.pm',
  EXE_FILES     => [ 'bin/filewiki' ],
  PREREQ_PM     => { 'Template'              => 0,
                     'Getopt::Std'           => 0,
                     'Date::Format'          => 0,
                     'Time::Piece'           => 0,
                     'HTML::Entities'        => 0,
                     'File::Path'            => 0,
                     'File::Spec::Functions' => 0,
                   },
);
