SoldatMistress - a GPL'd perl/gtk2 soldat admin client

 - By: jrgp - joe@u13.net

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
  sudo apt-get install libgtk2-perl libgtk2-notify-perl

On centos and probably also fedora with:
  sudo yum install perl-Gtk2 perl-Gtk2-Notify

On freebsd and macports, install or compile this port:
  p5-Gtk2

