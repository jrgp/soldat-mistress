SoldatMistress - a perl/gtk2 soldat admin client

 - By: jrgp - joe@u13.net
 - License: GNU General Public License (GPL)

===============================================

Features:
 - Manage/see players
 - Connect to multiple servers with tabs
 - Favorite servers list
 - Various configurable options
 - Optional console logging
 - Useful tray icon
 - Notification on !admin
 - runs on any unix-like os supporting the
 dependencies listed below.
 - et al.

===============================================

Caveats:
 - Can't really run on Windows because the windows port
 of perl/gtk2 is unmaintained and half works

===============================================

Install base gtk2 stuff on ubuntu/debian with:
  sudo apt-get install libgtk2-perl libgtk2-notify-perl libpango-perl libglib-perl

On centos (install rpmforge repo) and probably also fedora with:
  sudo yum install perl-Gtk2 perl-Gtk2-Notify perl-Pango perl-Glib

On openSUSE:
  zypper install perl-Gtk2

On freebsd and macports, install or compile this port:
  p5-Gtk2

If gtk2::notify was not installed via a package above, install it from cpan:
  Gtk2::Notify
