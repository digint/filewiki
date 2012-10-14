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

# install templates to /usr/share/filewiki/template
# this is a bit hacky, but I have no clue how to do this in a nicer way.

sub MY::post_constants {
    join("\n",
        'INSTALL_TEMPLATES_LIB=$(PREFIX)/share/filewiki/template',
        'DEST_INSTALL_TEMPLATES_LIB=$(DESTDIR)$(INSTALL_TEMPLATES_LIB)',
        'TEMPLATES_SRC_DIR=template');
}

sub MY::postamble {
    my $self = shift;
    my @text;
    push(@text,
        'install :: install.templates',
        '',
        'install.templates:: $(TEMPLATES_SRC_DIR)',
        "\t" . '$(NOECHO) $(MOD_INSTALL) $(TEMPLATES_SRC_DIR) $(DEST_INSTALL_TEMPLATES_LIB)');
    join("\n",@text);
}
