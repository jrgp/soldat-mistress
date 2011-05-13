
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

package Prefs;
use warnings;
use strict;
use Gtk2 -init;
use Gtk2::Helper;
use Gtk2::SimpleList;
use Gtk2::Gdk::Keysyms;
use Glib qw(TRUE FALSE);

# Constructor, bitches - start class, localize shit, set default settings
sub new {
	my ($class, $filename, $main_window) = @_;
	my $self = {};
	bless ($self, $class);
	$self->{main_window} = $main_window;
	$self->{filename} = $filename;
	$self->{pages} = {};
	$self->{settings} = {
		'favs.auto_connect' => '0',
		'logging.enable' => '0',
		'logging.naming' => '%i:%p_%n.log',
		'admin.notify' => '1',
		'admin.name' => 'User',
		'tray.enable' => '1',
		'tray.close_to' => '0'
	};
	$self->{widgets} = {};
	$self->{showing} = 0;
	$self;
}

#
#
#
################################################################################
## Settings management functions
################################################################################
#
#
#

# Parse settings file
sub load {
	my $self = shift;
	
	# Create sample settings file if it does not already exist
	unless (-e $self->{filename}) {
		return $self->save;
	}

	# Otherwise load settings, replacing default values
	open (my $handle, '<', $self->{filename}) || return 0;
	foreach (<$handle>) {
		if (m/^(?!\#)([^=]+)=([^\$]+)$/) {
			my ($k, $v) = ($1, $2);
			$k =~ s/^\s+|\s+$//g;
			$v =~ s/^\s+|\s+$//g;
			$self->{settings}->{$k} = $v;
		}
	}
	close $handle;
	1;
}

# Save current settings to file
sub save {
	my $self = shift;
	open (my $handle, '>', $self->{filename}) || return 0;
	foreach (keys %{$self->{settings}}) {
		print $handle "$_=".$self->{settings}->{$_}."\n";
	}
	close $handle;
	1;
}

# Return settings for use elsewhere
sub get_all {
	my $self = shift;
	return $self->{settings};
}

# Return a single setting key, or -1 if it doesn't exist
sub get {
	my ($self, $key) = @_;
	my $res;
	if (defined $self->{settings}->{$key}) {
		$res = $self->{settings}->{$key};
	}
	else {
		$res = defined $self->{default_settings}->{$key} ? $self->{default_settings}->{$key} : -1;
	}
	if (defined $_[2] && $_[2] eq 'int') {
		unless ($res =~ /^[\d\.]+$/) {
			$res = 0;
		}
	}
	$res;
}

# Save a setting, using usual key/value pair assignment
sub set {
	my ($self, $key, $value) = @_;
	$self->{settings}->{$key} = $value;
}

#
#
#
################################################################################
## GUI Related functions
################################################################################
#
#
#

# Show main GUI window
sub show_dialog {
	my ($self, $page) = @_;
	return if $self->{showing} == 1;
	$self->{showing} = 1;
	$self->{dialog_window} =  Gtk2::Dialog->new(
		'Soldat Mistress Preferences',
		$self->{server_window},
		[qw/modal destroy-with-parent/]
	);
	my $pref_book = Gtk2::Notebook->new;
	$pref_book->set_scrollable(TRUE);
	$self->{pages}->{settings} = $pref_book->append_page($self->get_settings_page(), 'Settings');
	$self->{pages}->{favs} = $pref_book->append_page($self->get_favs_page(), 'Favorite Servers');
	#$self->{pages}->{scripts} = $pref_book->append_page($self->get_scripting_page(), 'Scripting');
	$self->{pages}->{about} = $pref_book->append_page($self->get_about_page(), 'About');
	$pref_book->set_current_page($self->{pages}->{$page}) if defined $self->{pages}->{$page};
	$self->{dialog_window}->get_content_area()->add($pref_book);
	$self->{dialog_window}->show_all;
	my $resp = $self->{dialog_window}->run;
	$self->end_window;
}

# Deal with either closing the window naturally or forcing the bitch to fucking die
sub end_window {
	my $self = shift;
	
	# Window closed; do shit:
	$self->{favs}->save;
	$self->save_settings_page;
	$self->save;
	$self->{showing} = 0;

	# Important. Destroy the window *after* we get the data out of the fields it contains
	$self->{dialog_window}->destroy;
}

# Deal with getting values from settings tab when we're done
sub save_settings_page {
	my $self = shift;
	my $admin_name = $self->{widgets}->{set_uname}->get_text;
	$admin_name =~ s/^\s+|\s+$//g;
	$self->set('admin.name', $admin_name);
	$self->set('admin.notify', $self->{widgets}->{set_notif}->get_active == TRUE ? 1 : 0);
	$self->set('favs.auto_connect', $self->{widgets}->{set_autofav}->get_active == TRUE ? 1 : 0);
	$self->set('tray.enable', $self->{widgets}->{set_tray}->get_active == TRUE ? 1 : 0);
	$self->set('tray.close_to', $self->{widgets}->{set_ctray}->get_active == TRUE ? 1 : 0);
	$self->set('logging.enable', $self->{widgets}->{set_log_e}->get_active == TRUE ? 1 : 0);

	# Kill tray icon, if we want. Or, enable it...
	$self->{tray_icon}->set_visible($self->{widgets}->{set_tray}->get_active);
}

# Load contents of settings tab
sub get_settings_page {
	my $self = shift;
	my $vbox = Gtk2::VBox->new;
	my $al = Gtk2::Alignment->new(.5, 0, .5, 0);
	my $table = Gtk2::Table->new(5, 2, FALSE);
	$al->add($table);
	my ($x, $y) = (0, 1);
	foreach ((
		'Connect to favorites on startup',
		'Notify in-game players saying !admin',
		'Mistress icon in system tray',
		'Close to Tray',
		'Log console messages (to ~/.soldatmistress/logs/)',
		'Your Name (shows up in /clientlist and admin chat)'
	)) {
		my $l = Gtk2::Label->new($_.': ');
		$l->set_alignment(0, .5);
		$l->set_padding(5, 2);
		if ($_ eq 'Notify in-game players saying !admin') {
			$l->set_sensitive($self->{notif_enable} == 1 ? TRUE : FALSE);
		}
		$table->attach_defaults($l, 0, 1, $x++, $y++);
	}

	($x, $y) = (0, 1);
	foreach (qw(set_autofav set_notif set_tray set_ctray set_log_e)) {
		$self->{widgets}->{$_} = Gtk2::CheckButton->new;
		$table->attach_defaults($self->{widgets}->{$_}, 1, 2, $x++, $y++);
	}
	$self->{widgets}->{set_uname} = Gtk2::Entry->new;
	$table->attach_defaults($self->{widgets}->{set_uname}, 1, 2, $x++, $y++);
	$self->{widgets}->{set_uname}->set_width_chars(8);
	$self->{widgets}->{set_uname}->set_max_length(50);

	$self->{widgets}->{set_notif}->set_active($self->get('admin.notify', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_autofav}->set_active($self->get('favs.auto_connect', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_tray}->set_active($self->get('tray.enable', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_ctray}->set_active($self->get('tray.close_to', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_log_e}->set_active($self->get('logging.enable', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_uname}->set_text($self->get('admin.name'));

	$self->{widgets}->{set_notif}->set_sensitive($self->{notif_enable} == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_ctray}->set_sensitive($self->get('tray.enable', 'int') == 1 ? TRUE : FALSE);
	$self->{widgets}->{set_tray}->signal_connect (clicked => sub {
		$self->{widgets}->{set_ctray}->set_sensitive( $self->{widgets}->{set_tray}->get_active);
	});

	$vbox->add($al);
	$vbox->show_all;
	$vbox;
}

# Load contents of scripting tab
sub get_scripting_page {
	my $self = shift;
	my $vbox = Gtk2::VBox->new;
	$vbox->show_all;
	$vbox;
}

# Load contents of favs tab
sub get_favs_page {
	my $self = shift;
	my $vbox = Gtk2::VBox->new;
	my $favs_list = Gtk2::SimpleList->new(
		'IP' => 'text',
		'Port' => 'int',
		'Password' => 'text'
	);
	map { $_->set_resizable (TRUE) } $favs_list->get_columns;
	$favs_list->set_rules_hint (TRUE);
	$favs_list->set_reorderable (FALSE);
	my $favs_list_scrollbox = Gtk2::ScrolledWindow->new (undef, undef);
	$favs_list_scrollbox->set_policy ('automatic', 'automatic');
	$favs_list_scrollbox->add($favs_list);
	$vbox->add($favs_list_scrollbox);
	my $fav_add_frame = Gtk2::Frame->new('Add');
	my $fav_add_al = Gtk2::Alignment->new(0, 0, 0, 0);
	$fav_add_frame->add($fav_add_al);
	my $fav_add_host = Gtk2::Entry->new();
	my $fav_add_port = Gtk2::Entry->new();
	my $fav_add_pw = Gtk2::Entry->new();
	my $fav_add_host_l = Gtk2::Label->new('IP:');
	my $fav_add_port_l = Gtk2::Label->new('Port: ');
	my $fav_add_pw_l = Gtk2::Label->new('Password: ');
	$fav_add_port->set_max_length(6);
	$fav_add_port->set_width_chars(6);
	$fav_add_host->set_width_chars(15);
	$fav_add_pw->set_width_chars(15);
	my $fav_add_hbox = Gtk2::HBox->new();
	$fav_add_al->add($fav_add_hbox);
	my $fav_add_btn = Gtk2::Button->new_from_stock('gtk-add');
	$fav_add_hbox->add($fav_add_host_l);
	$fav_add_hbox->add($fav_add_host);
	$fav_add_hbox->add($fav_add_port_l);
	$fav_add_hbox->add($fav_add_port);
	$fav_add_hbox->add($fav_add_pw_l);
	$fav_add_hbox->add($fav_add_pw);
	$fav_add_hbox->add($fav_add_btn);
	$fav_add_hbox->show_all();
	$vbox->pack_end($fav_add_frame, FALSE, FALSE, 0);
	$vbox->show_all;
	foreach ($self->{favs}->get()) {
		push @{$favs_list->{data}}, [
			$_->{host},
			$_->{port},
			$_->{pw}
		];
	}
	$favs_list->signal_connect('button-press-event' => sub {
		my ($widget, $event) = @_;
		return FALSE unless $event->button == 3;
		return FALSE unless $event->window == $widget->get_bin_window;
		my ($menu);
		my ($x, $y) = $event->get_coords;
		my $server = $widget->get_path_at_pos($x, $y);
		return unless $server;
		$menu = Gtk2::Menu->new();
		my $host = $widget->{data}[$server->to_string][0];
		my $port = $widget->{data}[$server->to_string][1];
		my $kill_item = Gtk2::ImageMenuItem->new_from_stock('gtk-remove');
		$kill_item->signal_connect('activate' => sub {
			$self->{favs}->remove($host, $port);
			@{$widget->{data}} = ();
			foreach ($self->{favs}->get()) {
				push @{$widget->{data}}, [
					$_->{host},
					$_->{port},
					$_->{pw}
				];
			}
		});
		$menu->append($kill_item);
		$menu->popup(undef, undef, undef, undef, $event->button, $event->time);
		$menu->show_all;
	});
	$fav_add_btn->signal_connect('clicked' => sub {
		my ($widget, $event, $this) = @_;
		my ($a_host, $a_port, $a_pw) = (
			$fav_add_host->get_text,
			$fav_add_port->get_text,
			$fav_add_pw->get_text
		);
		$a_host =~ s/^\s+|\s+$//g;
		$a_port =~ s/^\s+|\s+$//g;
		$a_pw =~ s/^\s+|\s+$//g;
		if ($a_host eq '') {
			$self->gui_notif("Oh Fuck!", "You didn't fill in the address");
			return;
		}
		unless ($a_port =~ m/^\d+$/ && $a_port > 0 && $a_port < 65535) {
			$self->gui_notif("Oh Fuck!", 'You gave me an invalid port.');
			return;
		}
		if ($a_pw eq '') {
			$self->gui_notif("Oh Fuck!", "You didn't fill in the password");
			return;
		}
		$fav_add_host->set_text('');
		$fav_add_port->set_text('');
		$fav_add_pw->set_text('');
		$self->{favs}->add($a_host, $a_port, $a_pw);
		@{$favs_list->{data}} = ();
		foreach ($self->{favs}->get()) {
			push @{$favs_list->{data}}, [
				$_->{host},
				$_->{port},
				$_->{pw}
			];
		}
	});
	$vbox;
}

# Load contents of about tab
sub get_about_page {
	my $self = shift;
	my $vbox = Gtk2::VBox->new;
	$vbox->add(Gtk2::Image->new_from_file('gfx/logo.png')) if -e 'gfx/logo.png';
	$vbox->add(Gtk2::Label->new(
		'Soldat Mistress, an admin client for Unix Users'."\n".
		'(c) 2011 Joe Gillotti [jrgp] <joe@u13.net>'."\n".
		'Source code licensed under GPL'));
	$vbox->show_all;
	$vbox;
}

# bitch and moan, like the little cunt you are
sub gui_notif {
	my ($self, $title, $msg) = @_;
	my $dialog =  Gtk2::Dialog->new(
		$title,
		$self->{dialog_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept',
	);
	$dialog->get_content_area()->add(Gtk2::Label->new($msg));
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
}

1;
