FileWiki
========

FileWiki is a simple but powerful web site generator, written in
Perl. It provides a framework for creating and maintaining web sites,
by combining tools for template creation, markup language processing
and content management.

If you are looking for a polished ready-to-deploy web application,
FileWiki is not for you. It is a framework for creating web sites with
the tools YOU like, in a highly flexible, scriptable way. It
completely splits content management and page creation while giving
the user the freedom to use his preferred markup language and content
management system. It does not rely on any databases or web server
plugins. All you need is a web server which is capable of serving
static pages.

Web sites are generated out of a single directory tree containing
template, content and metadata files. The metadata defines the mapping
of source text to web content. For example the directories becomes a
menu structure and the files in it become its menu items. The metadata
within a specific page source can tell your template to just use a
different css class for the resulting page, or even do some scripted
magic.

FileWiki was designed to build corporate web sites or intranet sites
out of a CMS repository. For example, the webmaster can review the
commits from the editors, then install the new pages with a single
command. Another example is to use FileWiki as a commit-hook, updating
the web site automatically on every commit.

FileWiki comes with a command-line client, as well as a in-browser
Wiki editor.


Official home page: <http://www.digint.ch/filewiki>

Current version: `0.40`


DOCUMENTATION
-------------

You can find the main documentation in the `doc/` directory of the
FileWiki project. The latest version is also available [online]
(http://www.digint.ch/filewiki/doc/introduction.html).

The perl module documentation is distributed in POD format. The POD
pages are installed when you 'make install' and can be viewed using
'perldoc', e.g.

    perldoc FileWiki::Plugin::Gallery


INSTALLATION
------------

You can install FileWiki from the command line:

    perl Makefile.PL
    make install

Please see the separate installation documentation in
`doc/20-Installation.txt` for further information.


DEVELOPMENT
-----------

The source code for FileWiki is managed using Git. Check out the
source repository like this:

    git clone git://dev.tty0.ch/filewiki.git

If you would like to contribute or found bugs:

- visit the [FileWiki project page on GitHub] and use the [issues
  tracker] there
- talk to us on Freenode in #filewiki
- contact the author via email (the email address can be found in the
  sources)

Any feedback is appreciated!

  [FileWiki project page on GitHub]: http://github.com/digint/filewiki
  [issues tracker]: http://github.com/digint/filewiki/issues


SUPPORT
-------

If you need further information or find bugs, please contact the
author.


AUTHOR
------

Axel Burri <axel@tty0.ch>


COPYRIGHT AND LICENSE
---------------------

Copyright (C) 2011-2014 Axel Burri. All rights reserved.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
