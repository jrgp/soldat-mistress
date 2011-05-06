#!/usr/bin/env perl

# This file is part of Soldat Mistress (c) 2011 Joe Gillotti.
# 
# Soldat Mistress is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# Soldat Mistress is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with Soldat Mistress.  If not, see <http://www.gnu.org/licenses/>.
 

# We're fucking perfectionists
use warnings;
use strict;

# Need our libraries to better finger the gspot
use Gtk2 -init;
use Glib qw(TRUE FALSE);
use Gtk2::Gdk::Keysyms;

# Get all pithy, er, pathy
use File::Basename;

# Path shit
use lib dirname(__FILE__).'/lib/';
my $here = dirname($0);
chdir $here unless $here eq '.';

# Load our custom classes
use Server;
use Prefs;
use Favorites;

# Kill stdout buffer so shit flies immediately
BEGIN { $| = 1 }

# Start the main gui shit
my $server_window = new Gtk2::Window("toplevel");
my $window_vbox = Gtk2::VBox->new;
my $al = Gtk2::Alignment->new(0, 0, 0, 0);
my $tabs_hbox = Gtk2::HBox->new;
my $server_notebook = Gtk2::Notebook->new;
my $add_btn = Gtk2::Button->new('New Tab');
my $rem_btn = Gtk2::Button->new('Kill Tab');
my $con_btn = Gtk2::Button->new('Connect Favorites');
my $conf_btn = Gtk2::Button->new_from_stock('gtk-preferences');
my $tray_icon = Gtk2::StatusIcon->new_from_file('gfx/icon_x.png');
$server_notebook->set_scrollable(TRUE);
$server_window->set_default_icon_from_file('gfx/icon_x.png') if  -e 'gfx/icon_x.png';
$server_window->set_title("Soldat Mistress!");
$server_window->show_all;
$tabs_hbox->add($add_btn);
$tabs_hbox->add($rem_btn);
$tabs_hbox->add($con_btn);
$tabs_hbox->add($conf_btn);
$al->add($tabs_hbox);
$window_vbox->pack_start($al, FALSE, FALSE, 0);
$window_vbox->add($server_notebook);
$server_notebook->show_all;
$window_vbox->show_all;
$tabs_hbox->show_all;
$server_window->add($window_vbox);


# Load our favorites for the first time
my $favs = Favorites->new('favs.txt');
$favs->load();

# And our preferences
my $prefs = Prefs->new('prefs.conf', $server_window); 
$prefs->{favs} = $favs;
$prefs->load();

# When we die, really die
$server_window->signal_connect (delete_event => sub {Gtk2->main_quit;});

# Tray icon madness
if ($prefs->get('tray.enable') == 1) {
	$tray_icon->set_tooltip('Soldat Mistress');
	$tray_icon->set_visible(TRUE);
	$tray_icon->signal_connect('activate', \&tray_act);
	$tray_icon->signal_connect('popup-menu', \&tray_rl);
}
else {
	$tray_icon->set_visible(FALSE);
}

# Start delete button off as dead
$rem_btn->set_sensitive(FALSE);

# Store server objects here
my @nervs;

# Make a new server
sub create_server {
	my $server = Server->new();
	$server->set_window($server_window);
	my $sbox = Gtk2::HBox->new;
	$server->{widgets}->{tab_label} = Gtk2::Label->new('Server');
	$server->{widgets}->{tab_pic} = Gtk2::Image->new_from_file('gfx/disconnected.png');
	$sbox->add($server->{widgets}->{tab_pic});
	$sbox->add($server->{widgets}->{tab_label});
	$sbox->show_all;
	my $n = $server_notebook->append_page_menu(
		$server->get_gui(),
		$sbox,
		undef
	);
	$server_notebook->set_current_page($n);
	$rem_btn->set_sensitive(TRUE) if $server_notebook->get_n_pages() > 1;
	return push(@nervs, $server) - 1;
}

# Kill current
sub kill_server {
	return 0 unless $server_notebook->get_n_pages() > 1;
	my $cur = $server_notebook->get_current_page();
	for (my $i = 0; $i < scalar @nervs; $i++) {
		my $ts = $server_notebook->page_num($nervs[$i]->get_gui());
		if ($cur == $ts) {
			$nervs[$i]->kill_us;
			splice @nervs, $i, 1;
			last;
		}
	}
	$server_notebook->remove_page($cur);
	$rem_btn->set_sensitive(FALSE) unless $server_notebook->get_n_pages() > 1;
	1;
}

# Connect to the servers in our favorites
sub connect_favs {

	my $connected = 0;

	# Each of the favorite servers
	foreach (@{$favs->get()}) {

		# Skip this server if we already have a tab in it
		my $do_this = 1;
		for (my $i = 0; $i < scalar @nervs; $i++) {
			my $ts = $server_notebook->page_num($nervs[$i]->get_gui());
			if (
				defined $nervs[$i]->{settings} && 
				$nervs[$i]->{settings}->{host} eq $_->{host} &&
				$nervs[$i]->{settings}->{port} eq $_->{port}
			) {
				$do_this = 0;
				last;
			}
		}
		
		# Go for it
		if ($do_this == 1) {
			my $n = create_server();
			$nervs[$n]->{widgets}->{conn_port_txt}->set_text($_->{port});
			$nervs[$n]->{widgets}->{conn_addr_txt}->set_text($_->{host});
			$nervs[$n]->{widgets}->{conn_pw_txt}->set_text($_->{pw});
			$nervs[$n]->connect($_);
			$connected++;
		}
	}

	$connected;
}



# Callbacks
$add_btn->signal_connect(clicked => sub{create_server;});
$rem_btn->signal_connect(clicked => sub{kill_server;});
$con_btn->signal_connect('button-press-event' => sub {
	my ($widget, $event) = @_;
	my $fav_menu = Gtk2::Menu->new();
	my $con_all = Gtk2::MenuItem->new('Connect to all');
	$con_all->signal_connect('activate' => sub {
		connect_favs;	
	});
	$fav_menu->append($con_all);
	my $manage_favs = Gtk2::MenuItem->new('Edit Favorites');
	$manage_favs->signal_connect('activate' => sub {
		$prefs->show_dialog('favs');
	});
	$fav_menu->append($manage_favs);
	unless ($favs->num == 0) {
		$fav_menu->add(Gtk2::SeparatorMenuItem->new);
		foreach (@{$favs->get()}) {
			my $fsm = Gtk2::MenuItem->new($_->{host}.':'.$_->{port});
			$fsm->signal_connect('activate' => sub {
				my ($host, $port, $pw) = @{$_[1]};
				for (my $i = 0; $i < scalar @nervs; $i++) {
					my $ts = $server_notebook->page_num($nervs[$i]->get_gui());
					if (
						defined $nervs[$i]->{settings} && 
						$nervs[$i]->{settings}->{host} eq $host &&
						$nervs[$i]->{settings}->{port} eq $port
					) {
						$server_notebook->set_current_page($ts);
						return;
					}
				}
				my $n = create_server();
				$nervs[$n]->{widgets}->{conn_port_txt}->set_text($port);
				$nervs[$n]->{widgets}->{conn_addr_txt}->set_text($host);
				$nervs[$n]->{widgets}->{conn_pw_txt}->set_text($pw);
				$nervs[$n]->connect({
					host => $host, 
					port => $port,
					pw => $pw
				}) || $nervs[$n]->gui_notif('Oh Fuck!', 'Couldn\'t connect');
			}, [$_->{host}, $_->{port}, $_->{pw}]);
			$fav_menu->append($fsm);
		}
	}
	$fav_menu->popup(undef, undef, undef, undef, $event->button, $event->time);
	$fav_menu->show_all;
	$widget->leave;
});
$conf_btn->signal_connect(clicked => sub{$prefs->show_dialog('settings');});

# Left clicking the tray icon
sub tray_act {
	# todo
}

# Right clicking the tray icon
sub tray_rl {
	my ($widget, $button, $time) = @_;
	my $menu = Gtk2::Menu->new();

	my $s_btn = Gtk2::ImageMenuItem->new_from_stock('gtk-preferences');
	$s_btn->signal_connect('activate' => sub{$prefs->show_dialog('settings');});
	$menu->add($s_btn);
	$menu->add(Gtk2::SeparatorMenuItem->new);
	for (my $i = 0; $i < scalar @nervs; $i++) {
		my $sn = $server_notebook->page_num($nervs[$i]->get_gui());
		my $al = $nervs[$i]->check_connected();
		my $sm = Gtk2::ImageMenuItem->new(
			$nervs[$i]->{widgets}->{tab_label}->get_text.
			($al ? ' ('.
				($nervs[$i]->{stats}->{num_players} - $nervs[$i]->{stats}->{num_bots}).
				$nervs[$i]->{stats}->{max_players}.
				($nervs[$i]->{stats}->{num_bots} > 0 ? ' +'.$nervs[$i]->{stats}->{num_bots}.'' : '')
			.')' : '').
			($server_notebook->get_current_page() == $sn ? ' * ' : '')
		);
		$sm->set_image(Gtk2::Image->new_from_file(
			$al ? 'gfx/connected.png' : 'gfx/disconnected.png'
		));
		$sm->signal_connect('activate' => sub {
			$server_notebook->set_current_page($sn);
		});
		$menu->add($sm);
	}

	$menu->add(Gtk2::SeparatorMenuItem->new);
	my $q_btn = Gtk2::ImageMenuItem->new_from_stock('gtk-close');
	$q_btn->signal_connect('activate' => sub{Gtk2->main_quit;});
	$menu->add($q_btn);
	$menu->show_all;
	my ($x, $y, $push_in) = Gtk2::StatusIcon::position_menu($menu, $widget);
	$menu->popup(undef, undef, sub{return ($x,$y,0)}, undef, $button, $time);
	return 1;
}

# Connect to favorites if we want to
if ($prefs->get('favs.auto_connect') == 1) {
	# Yet start empty server if there are none
	create_server if connect_favs == 0;
}

# Otherwise start empty server entry
else {
	create_server;
}

# Start up gtk
Gtk2->main;
