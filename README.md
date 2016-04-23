# SoldatMistress - a perl/gtk2 soldat admin client

- By: jrgp - joe@u13.net (c) 2011
- License: GNU General Public License (GPL)

This is a feature-complete Soldat server admin client I wrote in perl back in 2011. This is
likely the first Soldat admin client I've written over the years. I'm migrating it here
from [Sourceforge](https://sourceforge.net/projects/soldatmistress/).

![Screenshot](http://jrgp.us/screenshots/soldatmistress/perl_soladmin17.png)

[Heaps more screenshots here](http://jrgp.us/screenshots/soldatmistress/)


## Features:
- Manage/see players
- Connect to multiple servers with tabs
- Favorite servers list
- Various configurable options
- Optional console logging
- Useful tray icon
- Desktop notifications (libnotify) on !admin
- Runs on any unix-like os supporting the dependencies listed below.
- et al.

## Run

    ./SoldatMistress.pl

## Dependencies
Install base gtk2 stuff on ubuntu/debian with:

    sudo apt-get install libgtk2-perl libgtk2-notify-perl libpango-perl libglib-perl

On CentOS/RHEL (install rpmforge repo) and probably also fedora with:

    sudo yum install perl-Gtk2 perl-Gtk2-Notify perl-Pango perl-Glib

On openSUSE:

    zypper install perl-Gtk2

On Arch:

    packman -S gtk2-perl

On freebsd and macports, install or compile this port:

    p5-Gtk2

If gtk2::notify was not installed via a package above, install it from cpan. This will
likely also require you to install the development packages for gtk2 and libnotify

    Gtk2::Notify
