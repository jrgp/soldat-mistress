
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

package Server;
use warnings;
use strict;
use IO::Socket; 
use Socket;
use POSIX;
use Gtk2 -init;
use Gtk2::Helper;
use Gtk2::SimpleList;
use Gtk2::Gdk::Keysyms;
use Glib qw(TRUE FALSE);

# Random bullshit
our @team_names = qw(None Alpha Bravo Charlie Delta Spectator);
our @team_colors = qw(black red blue green yellow purple);
our @mode_names = qw(DM PM TM CTF RM INF HTF);

#
#
#
################################################################################
## Our Object
################################################################################
#
#
#

# Constructor
sub new {
	my ($class) = @_;
	my $self = {};
	bless ($self, $class);
	$self->{sock} = 0;
	$self->{version} = '';
	$self->{s_buff} = '';
	$self->{s_line} = '';
	$self->{stats} = {};
	$self->{stats}->{players} = ();
	$self->{stats}->{max_players} = '';
	$self->{widgets} = {};
	$self->{support_ip2c} = 0;
	$self->init_gui();
	$self;
}

#
#
#
################################################################################
## Socket related functions
################################################################################
#
#
#

# Attempt connecting to server, logging in, and requesting REFRESH for the first time
sub connect {
	my ($self, $settings) = @_;
	$self->{settings} = $settings;
	$self->{sock} = new IO::Socket::INET (
		PeerAddr => $self->{settings}->{host},
		PeerPort => $self->{settings}->{port},
		Proto => 'tcp') || return 0;
	$self->realsend($self->{settings}->{pw}."\n");
	$self->realsend("/Maxplayers\n");
	$self->realsend("REFRESH\n");
	$self->{sock_watch} = Gtk2::Helper->add_watch (fileno $self->{sock}, 'in', sub{$self->watch_callback();});
	$self->{periodic_refresh} = Glib::Timeout->add (5000, sub{$self->auto_refresh();});
	$self->{periodic_time_dec} = Glib::Timeout->add (1000, sub{$self->auto_dec_time();});
	$self->{widgets}->{tab_label}->set_text($self->{settings}->{host}.':'.$self->{settings}->{port});
	$self->{widgets}->{tab_pic}->set_from_file('gfx/connected.png');
	$self->reset_conn_form();
	1;
}

# What happens when we want to disconnect
sub end_socket {
	my $self = shift;
	Gtk2::Helper->remove_watch($self->{sock_watch}) if $self->{sock_watch};
	Glib::Source->remove ($self->{periodic_refresh}) if $self->{periodic_refresh};
	Glib::Source->remove ($self->{periodic_time_dec}) if $self->{periodic_time_dec};
	close $self->{sock} if $self->{sock};
	$self->revive_conn_form();
	$self->empty_gui();
	if (defined $self->{settings}) {
		$self->{widgets}->{tab_label}->set_text($self->{settings}->{host}.':'.$self->{settings}->{port}.' (Disconnected)');
	}
	$self->{widgets}->{tab_pic}->set_from_file('gfx/disconnected.png');
}

# Hopefully a good way of determening if we're alive or not
sub check_connected {
	my $self = shift;
	if ($self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected) {
		return 1;
	}
	else {
		return 0;
	}
}

# Auto refresh!
sub auto_refresh {
	my $self = shift;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	$self->realsend("REFRESH\n");
	return 1;
}

# Whenever we get data from socket, it starts here
sub watch_callback {
	my $self = shift;
		
	if (not sysread($self->{sock}, $self->{s_buff}, 1)) {
		$self->end_socket();
		return 1;
	}
	else {
		if ($self->{s_buff} eq "\n") {
			if ($self->{s_line} eq "Invalid password.\r") {
				$self->console_add("[**] Bad Password...");
				$self->end_socket();
				$self->gui_notif('Oh Fuck!', 'Bad Password');
				$self->{s_line} = "";
				return 1;
			}
			elsif ($self->{s_line} eq "REFRESH\r") {
				$self->parse_refresh();
				$self->update_gui();
			}
			elsif ($self->{version} eq '' && $self->{s_line} =~ m/^Server Version: ([0-9\.]+)/){
				$self->{version} = $1;
			}
			elsif ($self->{s_line} =~ m/^Max players is ([0-9]+)/) {
				$self->{stats}->{max_players} = '/'.$1;
			}
			else {
				$self->console_add($self->{s_line});
			}
			if ($self->{s_line} =~ m/^\[(.+)\] ([^\$]+)$/) {
				$self->on_player_speak($1, $2);
			}
			$self->{s_line} = "";
		}
		else {
			$self->{s_line} .= $self->{s_buff};
		}
	}
	1;
}

# Parse refresh data to get current server info
sub parse_refresh {
	my $self = shift;

	my ($i, $sbuff, $len, $buff);

	$self->{stats}->{num_players} = 0;
	$self->{stats}->{num_bots} = 0;

	# Get player names and calculate the number of players based on empty nicks
	for ($i = 0; $i < 32; $i++) {

		# Get length of name
		sysread($self->{sock}, $sbuff, 1);
		$len = unpack('C', $sbuff);

		# Get name using length
		sysread($self->{sock}, $buff, $len);

		# Skip filler
		sysread($self->{sock}, $sbuff, 24 - $len);
		
		# Start player reference
		$self->{stats}->{players}[$i] = {};

		# Save name
		$self->{stats}->{players}[$i]->{'name'} = $buff;

		# Increase player count if need be
		$self->{stats}->{num_players}++ if $self->{stats}->{players}[$i]->{'name'} ne '';
	}

	# Get player teams
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 1);
		$self->{stats}->{players}[$i]->{'team'} = unpack('C', $sbuff);
	}
	
	# Get player kills
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 2);
		$self->{stats}->{players}[$i]->{'kills'} = unpack('S', $sbuff);
	}
	
	# Get player deaths
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 2);
		$self->{stats}->{players}[$i]->{'deaths'} = unpack('S', $sbuff);
	}
	
	# Get player pings
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 1);
		$self->{stats}->{players}[$i]->{'ping'} = unpack('C', $sbuff);
	}
	
	# Get player IDs
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 1);
		$self->{stats}->{players}[$i]->{'id'} = unpack('C', $sbuff);
	}

	# Get player IPs, and calculate the number of bots
	for ($i = 0; $i < 32; $i++) {
		sysread($self->{sock}, $sbuff, 4);
		$self->{stats}->{players}[$i]->{'ip'} = join('.', unpack('CCCC', $sbuff));
		$self->{stats}->{players}[$i]->{'ip'} = $self->{stats}->{players}[$i]->{'ip'} eq '0.0.0.0' ? 'Bot' : $self->{stats}->{players}[$i]->{'ip'};
		$self->{stats}->{num_bots}++ if $self->{stats}->{players}[$i]->{'ip'} eq 'Bot' and $self->{stats}->{players}[$i]->{'name'} ne '';
	}

	# red team score
	sysread($self->{sock}, $sbuff, 2);
	$self->{stats}->{'score_alpha'} = unpack('S', $sbuff);

	# blue team score
	sysread($self->{sock}, $sbuff, 2);
	$self->{stats}->{'score_bravo'} = unpack('S', $sbuff);

	# charlie score
	sysread($self->{sock}, $sbuff, 2);
	$self->{stats}->{'score_charlie'} = unpack('S', $sbuff);

	# delta score
	sysread($self->{sock}, $sbuff, 2);
	$self->{stats}->{'score_delta'} = unpack('S', $sbuff);
	
	# map name len
	sysread($self->{sock}, $sbuff, 1);
	$len  = unpack('C', $sbuff);
	sysread($self->{sock}, $buff, $len);
	$self->{stats}->{'map'} = $buff;
	sysread($self->{sock}, $sbuff, 16 - $len);

	# Time limit
	sysread($self->{sock}, $sbuff, 4);
	$self->{stats}->{'time_limit'} = ceil(unpack('L', $sbuff) / 60);
	sysread($self->{sock}, $sbuff, 4);
	$self->{stats}->{'current_time'} = ceil(unpack('L', $sbuff) / 60);

	#print $self->{stats}->{'time_limit'} ."\n";
	
	# Kill limit
	sysread($self->{sock}, $sbuff, 2);
	$self->{stats}->{'kill_limit'} = unpack('S', $sbuff);

	# Mode
	sysread($self->{sock}, $sbuff, 1);
	$self->{stats}->{'game_mode'} = $mode_names[unpack('C', $sbuff)];
}

# Try to reliably send data across the socket
sub realsend {
	my ($self, $msg) = @_;

	my $total_len = length($msg);
	my $len_sofar = 0;
	my $buff;
	while ($len_sofar < $total_len) {
		$buff = syswrite ($self->{sock}, substr($msg, $len_sofar));
		if (defined $buff) {
			$len_sofar += $buff;
		}
		else {
			return 0;
		}
	}
	return 1;
}

#
#
#
################################################################################
## GUI related functions
################################################################################
#
#
#

# Localize the main window to which we're attaching
sub set_window {
	my ($self, $window) = @_;
	$self->{main_window} = $window;
}

# Kill this server tab
sub kill_us {
	my $self = shift;
	$self->end_socket();
}

# Start base widgets and pack shit
sub init_gui() {
	my $self = shift;

	# Get common things batch defined. Saves zillions of lines of code
	$self->{widgets}->{$_} = Gtk2::VBox->new(FALSE, 5) foreach (qw(side_vbox top_vbox content_vbox presets_vbox)); 
	$self->{widgets}->{$_} = Gtk2::HBox->new(FALSE, 5) foreach (qw(main_window_hbox conn_hbox cs_box));
	$self->{widgets}->{$_} = Gtk2::Entry->new() foreach (qw(conn_addr_txt conn_port_txt conn_pw_txt cs_entry));

	# Frames
	$self->{widgets}->{conn_frame} = Gtk2::Frame->new('Connection');
	$self->{widgets}->{info_frame} = Gtk2::Frame->new('Quick Info');
	$self->{widgets}->{presets_frame} = Gtk2::Frame->new('Operation Presets');

	# Buttons
	$self->{widgets}->{conn_btn} = Gtk2::Button->new_from_stock('gtk-connect');
	$self->{widgets}->{dis_btn} = Gtk2::Button->new_from_stock('gtk-disconnect');
	$self->{widgets}->{cs_btn} = Gtk2::Button->new_from_stock('gtk-execute');

	# Labels
	$self->{widgets}->{conn_pw_label} = Gtk2::Label->new_with_mnemonic('Password: ');
	$self->{widgets}->{conn_addr_label} = Gtk2::Label->new_with_mnemonic('_Host: ');
	$self->{widgets}->{conn_port_label} = Gtk2::Label->new_with_mnemonic('Port: ');

	# Set shit
	$self->{widgets}->{conn_pw_txt}->set_visibility(FALSE);
	$self->{widgets}->{conn_port_txt}->set_max_length(6);
	$self->{widgets}->{conn_port_txt}->set_width_chars(6);
	$self->{widgets}->{conn_pw_label}->set_mnemonic_widget($self->{widgets}->{conn_pw_txt});
	$self->{widgets}->{conn_addr_label}->set_mnemonic_widget($self->{widgets}->{conn_addr_txt});
	$self->{widgets}->{conn_port_label}->set_mnemonic_widget($self->{widgets}->{conn_port_txt});

	# Misc
	$self->{widgets}->{main_pane} = Gtk2::VPaned->new();
	$self->{widgets}->{conn_al} = Gtk2::Alignment->new(0, 0, 0, 0);
	$self->{widgets}->{info_texts} = {};

	# Get shit packed accordingly
	$self->{widgets}->{top_vbox}->pack_start($self->{widgets}->{conn_frame}, FALSE, FALSE, 0);
	$self->{widgets}->{main_window_hbox}->add($self->{widgets}->{content_vbox});
	$self->{widgets}->{conn_hbox}->add($self->{widgets}->{$_}) foreach(qw(conn_addr_label conn_addr_txt conn_port_label 
		conn_port_txt conn_pw_label conn_pw_txt conn_btn));
	$self->{widgets}->{conn_hbox}->pack_end($self->{widgets}->{dis_btn}, FALSE, FALSE, 0);
	$self->{widgets}->{conn_al}->add($self->{widgets}->{conn_hbox});
	$self->{widgets}->{conn_frame}->add($self->{widgets}->{conn_al});
	
	# Info table
	my @labels = ('Map', 'Game Mode', 'Num Players', 'Time Left', 'Score Limit', 'Version');
	$self->{widgets}->{info_table} = new Gtk2::Table(scalar @labels, 2, FALSE); 
	my ($x, $y) = (0, 1);
	foreach (@labels) {
		my $l = Gtk2::Label->new($_.': ');
		#$l->set_alignment(0, 1);
		$self->{widgets}->{info_table}->attach_defaults($l, 0, 1, $x++, $y++);
	}
	($x, $y) = (0, 1);
	foreach (qw(map mode np time kl ver)) {
		$self->{widgets}->{info_texts}->{$_} = Gtk2::Label->new('N/A');
		$self->{widgets}->{info_table}->attach_defaults($self->{widgets}->{info_texts}->{$_}, 1, 2, $x++, $y++);
	}

	$self->{widgets}->{side_vbox}->set_size_request (200,100);

	$self->{widgets}->{main_window_hbox}->pack_end($self->{widgets}->{side_vbox}, FALSE, FALSE, 0);
	$self->{widgets}->{info_frame}->add($self->{widgets}->{info_table});
	$self->{widgets}->{side_vbox}->pack_start($self->{widgets}->{info_frame}, FALSE, FALSE, 0);
	
	$self->{widgets}->{side_vbox}->pack_start($self->{widgets}->{presets_frame}, TRUE, TRUE, 0);
	
	# Player list
	$self->{widgets}->{player_list} = $self->{support_ip2c} ? Gtk2::SimpleList->new(
		'Country' => 'text',
		'ID' => 'int',
		'Team' => 'markup',
		'Name' => 'text',
		'Kills' => 'int',
		'Deaths' => 'int',
		'Ratio' => 'text',
		'Ping' => 'int',
		'IP' => 'text',
	):  Gtk2::SimpleList->new(
		'ID' => 'int',
		'Team' => 'markup',
		'Name' => 'text',
		'Kills' => 'int',
		'Deaths' => 'int',
		'Ratio' => 'text',
		'Ping' => 'int',
		'IP' => 'text',
	);
	$self->{widgets}->{player_list}->set_rules_hint (TRUE);
	$self->{widgets}->{player_list}->set_reorderable (FALSE);
	map { $_->set_resizable (TRUE) } $self->{widgets}->{player_list}->get_columns;
	
	$self->{widgets}->{player_list_scrollbox} = Gtk2::ScrolledWindow->new (undef, undef);
	$self->{widgets}->{player_list_scrollbox}->set_policy ('automatic', 'always');
	$self->{widgets}->{player_list_scrollbox}->set_size_request (500,300);
	$self->{widgets}->{player_list_scrollbox}->add($self->{widgets}->{player_list});
	$self->{widgets}->{main_pane}->pack1($self->{widgets}->{player_list_scrollbox}, TRUE, FALSE);
	
	# Server log
	$self->{widgets}->{server_log_scrollbox} = Gtk2::ScrolledWindow->new (undef, undef);
	$self->{widgets}->{server_log_scrollbox}->set_policy ('automatic', 'always');
	$self->{widgets}->{server_log_scrollbox}->set_size_request (500,100);

	my $font = Pango::FontDescription->new;
	$font->set_family('Monospace');

	$self->{widgets}->{server_log} = Gtk2::TextView->new;
	$self->{widgets}->{server_log}->modify_base('normal', Gtk2::Gdk::Color->new(0, 0, 0));
	$self->{widgets}->{server_log}->modify_text('normal', Gtk2::Gdk::Color->new(200*257, 200*257, 200*257));
	$self->{widgets}->{server_log}->modify_font($font);
	$self->{widgets}->{server_log}->set_left_margin(3);
	$self->{widgets}->{server_log}->set_right_margin(3);
	$self->{widgets}->{server_log}->set_editable(FALSE);
	$self->{widgets}->{server_log_buff} = $self->{widgets}->{server_log}->get_buffer;
	$self->{widgets}->{server_log_buff}->create_mark('end', $self->{widgets}->{server_log_buff}->get_end_iter, FALSE);
	$self->{widgets}->{server_log_buff}->signal_connect(insert_text => sub {
		$self->{widgets}->{server_log}->scroll_to_mark($self->{widgets}->{server_log_buff}->get_mark('end'), 0.0, TRUE, 0, 0.5);
	});

	$self->{widgets}->{server_log_scrollbox}->add($self->{widgets}->{server_log});
	$self->{widgets}->{main_pane}->pack2($self->{widgets}->{server_log_scrollbox}, TRUE, FALSE);
	$self->{widgets}->{content_vbox}->add($self->{widgets}->{main_pane});
	
	# CS
	$self->{widgets}->{cs_entry_label }= Gtk2::Label->new_with_mnemonic("_Execute:");

	$self->{widgets}->{cs_entry}->set_max_length(255);
	$self->{widgets}->{cs_entry}->set_editable(FALSE);

	$self->{widgets}->{cs_entry_label}->set_mnemonic_widget($self->{widgets}->{cs_entry});

	$self->{widgets}->{cs_box}->pack_start($self->{widgets}->{cs_entry_label}, FALSE, FALSE, 4);
	$self->{widgets}->{cs_box}->add($self->{widgets}->{cs_entry});

	$self->{widgets}->{content_vbox}->pack_end($self->{widgets}->{cs_box}, FALSE, FALSE, 2);

	$self->{widgets}->{cs_entry}->signal_connect('key_press_event' => sub {
		if ($_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'}) {
			$self->{widgets}->{cs_btn}->clicked;
			return 1;
		}
	});
	$self->{widgets}->{cs_box}->pack_end($self->{widgets}->{cs_btn}, FALSE, FALSE, 0);

	# Main vbox
	$self->{widgets}->{top_vbox}->add($self->{widgets}->{main_window_hbox});
	
	# Start shit out useless
	$self->{widgets}->{dis_btn}->set_sensitive(FALSE);
	$self->{widgets}->{cs_btn}->set_sensitive(FALSE);
	$self->{widgets}->{cs_entry}->set_sensitive(FALSE);

	# Presets action shiz
	$self->{widgets}->{presets_window} = Gtk2::ScrolledWindow->new (undef, undef);
	$self->{widgets}->{presets_store} = Gtk2::TreeStore->new(qw(Glib::String));
	$self->{preset_items} = {
		'Game' => [
			'Change Gamemode',
			'Restart Match',
			'Next Map',
			'Change Password'
		],
		'Mapping' => [
			'Pick new map',
			'Reload list',
			'Add Map',
			'Remove Map'
		],
		'Players' => [
			'Add admin',
			'Remove admin',
			'Kick last player',
			'Ban IP',
			'Unban IP',
			'Ban player name',
			'Unban player name',
			'Kick everyone',
			'Ban everyone',
			'Change Welcome',
			'Add Bot'
		]
	};
	foreach (keys %{$self->{preset_items}}) {
		my $iter = $self->{widgets}->{presets_store}->append(undef);
		$self->{widgets}->{presets_store}->set($iter, 0 => $_);
		$self->{widgets}->{presets_store}->set($self->{widgets}->{presets_store}->append($iter), 0 => $_) foreach (@{$self->{preset_items}{$_}});
	}

	$self->{widgets}->{presets_tv} = Gtk2::TreeView->new($self->{widgets}->{presets_store});
	my $presets_column = Gtk2::TreeViewColumn->new;
	$presets_column->set_title('Actions');
	my $presets_renderer = Gtk2::CellRendererText->new;
	$presets_column->pack_start($presets_renderer, FALSE);
	$presets_column->add_attribute($presets_renderer, text => 0);
	$self->{widgets}->{presets_tv}->append_column($presets_column);
	$self->{widgets}->{presets_window}->add($self->{widgets}->{presets_tv});
	$self->{widgets}->{presets_vbox}->add($self->{widgets}->{presets_window});
	my $btn_al = Gtk2::Alignment->new(1, 0, 0, 0);
	$self->{widgets}->{presets_btn} = Gtk2::Button->new('Do It');
	$btn_al->add($self->{widgets}->{presets_btn});
	$self->{widgets}->{presets_vbox}->pack_end($btn_al, FALSE, FALSE, 0);
	$self->{widgets}->{presets_window}->set_policy ('automatic', 'automatic');
	$self->{widgets}->{presets_frame}->add($self->{widgets}->{presets_vbox});
	$self->{widgets}->{presets_btn}->set_sensitive(FALSE);
	$self->{widgets}->{presets_tv}->set_sensitive(FALSE);
	
	# Show shit
	$self->{widgets}->{$_}->show_all()  foreach (qw(side_vbox top_vbox content_vbox)); 
	$self->{widgets}->{$_}->show_all()  foreach (qw(main_window_hbox conn_hbox cs_box));

	# Callbacks..
	$self->{widgets}->{conn_btn}->signal_connect(clicked => sub {
		my $port = $self->{widgets}->{conn_port_txt}->get_text();
		my $addr = $self->{widgets}->{conn_addr_txt}->get_text();
		my $pass = $self->{widgets}->{conn_pw_txt}->get_text() ;
		$port =~ s/^\s+|\s+$//g;
		$addr =~ s/^\s+|\s+$//g;
		$pass =~ s/^\s+|\s+$//g;
		if ($addr eq '') {
			$self->gui_notif("Oh Fuck!", "You didn't fill in the address");
			return;
		}
		unless ($port =~ m/^\d+$/ && $port > 0 && $port < 65535) {
			$self->gui_notif("Oh Fuck!", 'You gave me an invalid port.');
			return;
		}
		if ($pass eq '') {
			$self->gui_notif("Oh Fuck!", "You didn't fill in the password");
			return;
		}

		if ($self->connect({
			host => $addr,
			port => $port,
			pw => $pass
		}) == 1) {
		}
		else {
			$self->gui_notif("Oh Fuck!", "Couldn't connect");
		}
		
	});
	
	$self->{widgets}->{conn_addr_txt}->signal_connect('key_press_event' => sub {
		if ($_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'}) {
			$self->{widgets}->{conn_btn}->clicked;
			return 1;
		}
	});
	$self->{widgets}->{conn_port_txt}->signal_connect('key_press_event' => sub {
		if ($_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'}) {
			$self->{widgets}->{conn_btn}->clicked;
			return 1;
		}
	});
	$self->{widgets}->{conn_pw_txt}->signal_connect('key_press_event' => sub {
		if ($_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'}) {
			$self->{widgets}->{conn_btn}->clicked;
			return 1;
		}
	});

	$self->{widgets}->{dis_btn}->signal_connect(clicked => sub {$self->end_socket();});
	$self->{widgets}->{presets_btn}->signal_connect(clicked => sub {$self->handle_preset();});

	$self->{widgets}->{player_list}->signal_connect('button-press-event' => sub {
		my ($widget, $event) = @_;
		$self->player_rl_callback($widget, $event);
	});
	
	$self->{widgets}->{cs_btn}->signal_connect (clicked => sub{$self->cmd_send_callback();});

	# Start disconnect button off as hidden
	$self->{widgets}->{dis_btn}->hide();
}

# Handle when we click the Do It! button
# Calling this a kludge would be a compliment, but sometimes ugly code
# fits the bill perfectly.
sub handle_preset {
	my $self = shift;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	my $sel = $self->{widgets}->{presets_tv}->get_selection;
	return unless $sel->count_selected_rows == 1 && $sel->get_selected_rows->to_string =~ m/^(\d+):(\d+)$/;
	my @keys = keys %{$self->{preset_items}};
	my @vals = @{$self->{preset_items}{$keys[$1]}};
	my $desired_action = $vals[$2];

	# Handle each action
	if ($desired_action eq 'Restart Match') {
		$self->realsend("/restart\n");
	}
	elsif ($desired_action eq 'Next Map') {
		$self->realsend("/nextmap\n");
	}
	elsif ($desired_action eq 'Change Gamemode') {
		$self->change_gamemode;
	}
	elsif ($desired_action eq 'Pick new map') {
		$self->change_map;
	}
	elsif ($desired_action eq 'Change Password') {
		$self->change_pw;
	}
	elsif ($desired_action eq 'Add Bot') {
		$self->add_bot;
	}
	else {
		print "Must handle '$desired_action'\n";
	}
}

# Change map
sub change_map {
	my $self = shift;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	my $dialog =  Gtk2::Dialog->new(
		'Change map',
		$self->{server_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept',
		'gtk-cancel' => 'reject'
	);
	my $label = Gtk2::Label->new_with_mnemonic("_Map name?");
	my $map_entry = Gtk2::Entry->new;
	$label->set_mnemonic_widget($map_entry);
	$dialog->get_content_area()->add($label);
	$dialog->get_content_area()->add($map_entry);
	$map_entry->signal_connect('key_press_event' => sub {
		$dialog->response('accept') if $_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'};
	});
	$dialog->show_all;
	my $resp = $dialog->run();
	my $map_txt = $map_entry->get_text();
	$dialog->destroy;
	if ($resp eq 'accept') {
		$map_txt =~ s/^\s+|\s+$//g;
		return if $map_txt eq '';
		return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
		$self->realsend("/map $map_txt\n");
	}
}

# Change pw
sub change_pw {
	my $self = shift;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	my $dialog =  Gtk2::Dialog->new(
		'Change Game Password',
		$self->{server_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept',
		'gtk-cancel' => 'reject'
	);
	my $label = Gtk2::Label->new_with_mnemonic("_Password");
	my $pw_entry = Gtk2::Entry->new;
	$pw_entry->set_visibility(FALSE);
	$label->set_mnemonic_widget($pw_entry);
	$dialog->get_content_area()->add($label);
	$dialog->get_content_area()->add($pw_entry);
	$pw_entry->signal_connect('key_press_event' => sub {
		$dialog->response('accept') if $_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'};
	});
	$dialog->show_all;
	my $resp = $dialog->run();
	my $pw_txt = $pw_entry->get_text();
	$dialog->destroy;
	if ($resp eq 'accept') {
		$pw_txt =~ s/^\s+|\s+$//g;
	#	return if $pw_txt eq '';
		return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
		$self->realsend("/password $pw_txt\n");
	}
}

# Change gamemode
sub change_gamemode {
	my $self = shift;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	my $dialog =  Gtk2::Dialog->new(
		'Change gamemode',
		$self->{server_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept',
		'gtk-cancel' => 'reject'
	);
	my $label = Gtk2::Label->new_with_mnemonic("_Game mode");
	my $mode_entry = Gtk2::ComboBox->new_text;
	my $i = 0;
	foreach (@mode_names) {
		$mode_entry->append_text($_);
		$mode_entry->set_active($i) if $_ eq $self->{stats}->{'game_mode'};
		$i++;
	}
	$label->set_mnemonic_widget($mode_entry->child);
	$dialog->get_content_area()->add($label);
	$dialog->get_content_area()->add($mode_entry);
	$dialog->show_all;
	my $resp = $dialog->run;
	my $gname = $mode_entry->get_active_text;
	$dialog->destroy;
	if ($resp eq 'accept') {
		$i = 0;
		my $gid = -1;
		foreach (@mode_names) {
			if ($_ eq $gname) {
				$gid = $i;
				last;
			}
			$i++;
		}
		if ($gname ne $self->{stats}->{'game_mode'} && $gid > -1) {
			$self->realsend("/gamemode $gid\n");
		}
	}
}

# Handle command send
sub cmd_send_callback {
	my $self = shift;

	# If we aren't connected, fuck it
	return FALSE unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;

	# Text entry
	my $cmd = $self->{widgets}->{cs_entry}->get_text;

	# Empty field for next time around
	$self->{widgets}->{cs_entry}->set_text('');

	# Trim shit
	$cmd =~ s/^\s+|\s+$//g;

	# Bullshitting me?
	if ($cmd eq '') {
		$self->gui_notif("Oh Fuck!", "Comon man, gimme some shit to execute!");
		return;
	}

	# Getting pissy?
	if ($cmd =~ m/^(SHUTDOWN|REFRESHX?)$/i) {
		$self->gui_notif("Oh Fuck!", "Not letting you fuck shit up, sorry.");
		return;
	}

	# Want to be chatting instead?
	unless ($cmd =~ m/^[\/]/) {
		$self->{widgets}->{cs_entry}->set_text("/say $cmd");
		return;
	}
	
	# Give it
	$self->realsend($cmd."\n");
}


# Right click in player list call back
sub player_rl_callback {
	my ($self, $widget, $event) = @_;

	return FALSE unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;

	# No screwing around. We're specific
	return FALSE unless $event->button == 3;
	return FALSE unless $event->window == $self->{widgets}->{player_list}->get_bin_window;

	# init shit
	my ($menu);

	# Get the fucking values. 
	my ($x, $y) = $event->get_coords;
	my $p = $self->{widgets}->{player_list}->get_path_at_pos($x, $y);

	# If this isn't a player, offer to add a fucking bot
	unless ($p) {
		$menu = Gtk2::Menu->new();
		my $m_addbot = Gtk2::ImageMenuItem->new("Add a bot?");
		$m_addbot->signal_connect('activate' => sub{$self->add_bot();});
		$m_addbot->set_image(Gtk2::Image->new_from_file('gfx/addbot.png'));
		$menu->append($m_addbot);
		$menu->popup(undef, undef, undef, undef, $event->button, $event->time);
		$menu->show_all;
		return;
	}

	# It is a player; start gathering shit..
	my $pid = $self->{widgets}->{player_list}->{data}[$p->to_string][$self->{support_ip2c} ? 1 : 0];
	my $pname = $self->{widgets}->{player_list}->{data}[$p->to_string][$self->{support_ip2c} ? 3 : 2];
	my $pip = $self->{widgets}->{player_list}->{data}[$p->to_string][$self->{support_ip2c} ? 8 : 7];

	# Our popup menu
	$menu = Gtk2::Menu->new();

	# The cute fucking items
	my $m_kick = Gtk2::ImageMenuItem->new("Kick `$pname'");
	$m_kick->signal_connect('activate' => sub{$self->player_mod('kick', $pid, $pname, $pip);});
	$m_kick->set_image(Gtk2::Image->new_from_file('gfx/kick.png'));
	$menu->append($m_kick);

	# These only apply to real players
	unless ($pip eq 'Bot') {
		my $m_ban = Gtk2::ImageMenuItem->new("Ban `$pname'");
		my $m_banip = Gtk2::ImageMenuItem->new("IP-Ban `$pname' ($pip)");
		my $m_adm = Gtk2::ImageMenuItem->new("Give Admin to `$pname' ($pip)");
		my $m_dadm = Gtk2::ImageMenuItem->new("Take Admin from `$pname' ($pip)");
		$m_ban->signal_connect('activate' => sub{$self->player_mod('ban', $pid, $pname, $pip);});
		$m_banip->signal_connect('activate' => sub{$self->player_mod('banip', $pid, $pname, $pip);});
		$m_adm->signal_connect('activate' => sub{$self->player_mod('adm', $pid, $pname, $pip);});
		$m_dadm->signal_connect('activate' => sub{$self->player_mod('dadm', $pid, $pname, $pip);});
		$m_ban->set_image(Gtk2::Image->new_from_file('gfx/ban.png'));
		$m_banip->set_image(Gtk2::Image->new_from_file('gfx/ban.png'));
		$m_adm->set_image(Gtk2::Image->new_from_file('gfx/adm_give.png'));
		$m_dadm->set_image(Gtk2::Image->new_from_file('gfx/adm_revoke.png'));
		$menu->append($m_ban);
		$menu->append($m_banip);
		$menu->append($m_adm);
		$menu->append($m_dadm);
	}

	# Shove the menu where it goes
	$menu->popup(undef, undef, undef, undef, $event->button, $event->time);

	# Display the fucker once and for all
	$menu->show_all;
}

# Do something to a player somehow
sub player_mod {
	my ($self, $act, $pid, $pname, $pip) = @_;
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	my $cmd;
	if ($act eq 'kick') {
		$cmd = "/kick $pid";
	}
	elsif ($act eq 'ban') {
		$cmd = "/ban $pid";
	}
	elsif ($act eq 'banip') {
		$cmd = "/banip $pip";
	}
	elsif ($act eq 'adm') {
		$cmd = "/admip $pip";
	}
	elsif ($act eq 'dadm') {
		$cmd = "/unadm $pip";
	}
	else {
		return; 
	}
	$self->realsend($cmd."\n");
}

# Add a bot
sub add_bot {
	my $self = shift;

	# Don't bother if we aren't connected
	return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;

	# Spawn dialog window
	my $dialog =  Gtk2::Dialog->new(
		'Add a bot',
		$self->{server_window},
		[qw/modal destroy-with-parent/],
		'gtk-add' => 'accept',
		'gtk-cancel' => 'reject'
	);

	# Set up the label and text field
	my $label = Gtk2::Label->new_with_mnemonic("_Bot name?");
	my $bot_entry = Gtk2::ComboBoxEntry->new_text;
	$bot_entry->append_text($_) foreach((
		'Admiral',
		'Billy',
		'Blain',
		'Boogie Man',
		'Commando',
		'D Dave',
		'Danko',
		'Dutch',
		'John',
		'Kruger',
		'Roach',
		'Poncho',
		'Sniper',
		'Srg Mac',
		'Stevie',
		'Terminator'
	));
	$label->set_mnemonic_widget($bot_entry->child);

	# Attach them
	$dialog->get_content_area()->add($label);
	$dialog->get_content_area()->add($bot_entry);
	
	# Make pressing enter in the text field accept it 
	$bot_entry->child->signal_connect('key_press_event' => sub {
		$dialog->response('accept') if $_[1]->keyval == $Gtk2::Gdk::Keysyms{'Return'};
	});

	# Show it
	$dialog->show_all;

	# Wait for the shit to go down
	my $resp = $dialog->run();

	# Get the text after it goes down
	my $bot_txt = $bot_entry->child->get_text();

	# Fucking die
	$dialog->destroy;
	
	# Attempt doing it if the user accepted somehow
	if ($resp eq 'accept') {

		# Trim shit
		$bot_txt =~ s/^\s+|\s+$//g;

		# Fucker
		return if $bot_txt eq '';

		# I really hope we're connected
		return unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;

		# We are, send that fucking bot to hell!!!!!!!!!!!!
		$self->realsend("/addbot $bot_txt\n");
	}
}

# Return the main gui object for the "notebook"
sub get_gui() {
	my $self = shift;
	return $self->{widgets}->{top_vbox};
}

# Pop up a notification message
sub gui_notif {
	my ($self, $title, $msg) = @_;

	my $dialog =  Gtk2::Dialog->new(
		$title,
		$self->{main_window},
		[qw/modal destroy-with-parent/],
		'gtk-ok' => 'accept',
	);
	$dialog->get_content_area()->add(Gtk2::Label->new($msg));
	$dialog->show_all;
	$dialog->run;
	$dialog->destroy;
}

# Re-activate connect form and kill disconnect button
sub revive_conn_form {
	my $self = shift;
	$self->{widgets}->{dis_btn}->set_sensitive(FALSE);
	$self->{widgets}->{dis_btn}->hide();
	$self->{widgets}->{conn_btn}->show();
	$self->{widgets}->{$_}->set_sensitive(TRUE) foreach (qw(conn_addr_txt conn_port_txt conn_pw_txt conn_btn));
	# CLI command box
	$self->{widgets}->{cs_btn}->set_sensitive(FALSE);
	$self->{widgets}->{presets_btn}->set_sensitive(FALSE);
	$self->{widgets}->{presets_tv}->set_sensitive(FALSE);
}

# Kill connect form and activate disconnect button
sub reset_conn_form {
	my $self = shift;
	$self->{widgets}->{dis_btn}->show();
	$self->{widgets}->{conn_btn}->hide();
	$self->{widgets}->{dis_btn}->set_sensitive(TRUE);
	$self->{widgets}->{$_}->set_sensitive(FALSE) foreach (qw(conn_addr_txt conn_port_txt conn_pw_txt conn_btn));

	# CLI command box
	$self->{widgets}->{cs_btn}->set_sensitive(TRUE);
	$self->{widgets}->{cs_entry}->set_sensitive(TRUE);
	$self->{widgets}->{cs_entry}->set_editable(TRUE);
	
	# Preset shit
	$self->{widgets}->{presets_btn}->set_sensitive(TRUE);
	$self->{widgets}->{presets_tv}->set_sensitive(TRUE);
}

# Empty holders of info
sub empty_gui {
	my $self = shift;
	
	# Empty player list
	splice @{$self->{widgets}->{player_list}->{data}};
	
	# And info table
	$self->{widgets}->{info_texts}->{$_}->set_text('N/A') foreach (keys %{$self->{widgets}->{info_texts}});
	
	# And say we're outta
	$self->console_add("[**] Disconnected...");

	# Make useless things now literally useless
	$self->{widgets}->{cs_entry}->set_text('');
}

# Update holders of info
sub update_gui {
	my $self = shift;
	
	my $ip2c = IP::Country::Fast->new() if $self->{support_ip2c} == 1;
	
	# Kill contents
	@{$self->{widgets}->{player_list}->{data}} = ();

	# Save players
	foreach (@{$self->{stats}->{players}}) {
		# Skip empty player slots
		unless ($_->{'name'} eq '') {

			my $ratio = 0;

			if ($_->{'deaths'} == 0 && $_->{'kills'} > 0) {
				$ratio = $_->{'kills'};	
			}
			elsif ($_->{'deaths'} > 0 && $_->{'kills'} > 0) {
				$ratio = $_->{'kills'} % $_->{'deaths'} == 0 ? $_->{'kills'} / $_->{'deaths'}
				: sprintf("%.2f", $_->{'kills'} / $_->{'deaths'});
			}

			# Add player
			push @{$self->{widgets}->{player_list}->{data}},
				$self->{support_ip2c} ? 
					[$_->{'ip'} eq 'Bot' ? 'N/A' : $ip2c->inet_atocc($_->{'ip'}),
					$_->{'id'},
					'<span color="'.$team_colors[$_->{'team'}].'">'.$team_names[$_->{'team'}].'</span>',
					$_->{'name'},
					$_->{'kills'},
					$_->{'deaths'},
					$ratio,
					$_->{'ping'},
					$_->{'ip'}
					] : [$_->{'id'},
						'<span color="'.$team_colors[$_->{'team'}].'">'.$team_names[$_->{'team'}].'</span>',
						$_->{'name'},
						$_->{'kills'},
						$_->{'deaths'},
						$ratio,
						$_->{'ping'},
						$_->{'ip'}];
		}
	};
	
	# info table
	$self->{widgets}->{info_texts}->{'map'}->set_text($self->{stats}->{'map'});
	$self->{widgets}->{info_texts}->{'ver'}->set_text($self->{version});
	$self->{widgets}->{info_texts}->{'np'}->set_text(
		($self->{stats}->{num_players} - $self->{stats}->{num_bots} ) . $self->{stats}->{max_players} .
		($self->{stats}->{num_bots} > 0 ? ' ('.$self->{stats}->{num_bots}.' bots)' : '')
	);
	$self->{widgets}->{info_texts}->{'mode'}->set_text($self->{stats}->{'game_mode'});
	$self->{widgets}->{info_texts}->{'kl'}->set_text($self->{stats}->{'kill_limit'});
	$self->{widgets}->{info_texts}->{'time'}->set_text(
		sprintf("%d:%02d / %d:%02d", floor($self->{stats}->{'current_time'}/60), $self->{stats}->{'current_time'}%60, floor($self->{stats}->{'time_limit'}/60), $self->{stats}->{'time_limit'}%60)
	);
}

# Decrement time limit every second
sub auto_dec_time {
	my $self = shift;
	return 1 unless $self->{sock} != 0 && defined $self->{sock} && $self->{sock}->connected;
	return 1 unless $self->{stats}->{'current_time'} > 0;
	$self->{stats}->{'current_time'}--;
	$self->{widgets}->{info_texts}->{'time'}->set_text(
		sprintf("%d:%02d / %d:%02d", floor($self->{stats}->{'current_time'}/60), $self->{stats}->{'current_time'}%60, floor($self->{stats}->{'time_limit'}/60), $self->{stats}->{'time_limit'}%60)
	);
	1;
}

# Append a line to the console
sub console_add {
	my ($self, $line) = @_;
	my @time = localtime(time);
	$self->{widgets}->{server_log_buff}->insert(
		$self->{widgets}->{server_log_buff}->get_end_iter, 
		sprintf("[%02d:%02d:%02d] %s\n", $time[2], $time[1], $time[0], $line)
	);
}

# When a player speaks, do something
sub on_player_speak {
	my ($self, $player, $msg) = @_;
	$player =~ s/^\s+|\s+$//g;
	$msg =~ s/^\s+|\s+$//g;
	if ($msg =~ m/^\!(\S+) ?([^\$]+)?$/) {
		if ($1 eq 'admin' && $self->{notif_enable} && $self->{prefs}->get('admin.notify') == 1) {
			my $notif = Gtk2::Notify->new_with_status_icon(
				"$player in ".$self->{settings}->{host}.':'.$self->{settings}->{port},
				"$player called !admin".(defined $2 && length($2) > 0 ? ": $2" : ''),
				'gfx/icon_x.png',
				$self->{widgets}->{tray_icon}
			);
			$notif->show;
		}
	}
}


1;
