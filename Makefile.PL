use ExtUtils::MakeMaker;
my $template_src_dir = 'template';

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
sub MY::post_constants {
    join("\n",
        'TEMPLATES_DEST_DIR=$(PREFIX)/share/filewiki',
        "TEMPLATES_SRC_DIR=$template_src_dir");
}

sub MY::postamble {
    my $self = shift;
    my @text;

    push(@text,
        'install :: install.templates',
        '',
        'install.templates:: $(TEMPLATES_SRC_DIR)',
        "\t\$(MKPATH) \$(TEMPLATES_DEST_DIR)",
        "\t\$(CP) -r \$(TEMPLATES_SRC_DIR) \$(TEMPLATES_DEST_DIR)");
    join("\n",@text);
}
