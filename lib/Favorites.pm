
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

package Favorites;
use warnings;
use strict;

# Constructor, bitches
sub new {
	my ($class, $filename) = @_;
	my $self = {};
	bless ($self, $class);
	$self->{favorites} = ();
	$self->{filename} = $filename;
	$self;
}

# get number of favs
sub num {
	my $self = shift;
	return scalar @{$self->{favorites}};
}

# Add a server to favorites
sub add {
	my ($self, $host, $port, $pw) = @_;
	push @{$self->{favorites}}, {
		host => $host,
		port => $port,
		pw => $pw
	};
}

# Get the favorites
sub get {
	my $self = shift;
	my %seen;
	my $res;
	foreach (@{$self->{favorites}}) {
		unless (defined $seen{$_->{host}.$_->{port}}) {
			$seen{$_->{host}.$_->{port}} = 1;
			push @{$res}, {
				host => $_->{host},
				port => $_->{port},
				pw => $_->{pw}
			};
		}
	}
	$res;
}

# We have this server in our favorites?
sub check_existing {
	my ($self, $host, $port) = @_;
	foreach (@{$self->{favorites}}) {
		return 1 if $_->{host} eq $host && $_->port eq $port;
	}
	return 0;
}

# Remove this server from favorites
sub remove {
	my ($self, $host, $port) = @_;
	my $new = ();
	foreach (@{$self->{favorites}}) {
		unless ($_->{host} eq $host && $_->{port} eq $port) {
			push @{$new}, {
				host => $_->{host},
				port => $_->{port},
				pw => $_->{pw}
			};
		}
	}
	$self->{favorites} = $new;
}

# Remove dups
sub kill_dups {
	my $self = shift;
	my %seen;
	my $new;
	foreach (@{$self->{favorites}}) {
		unless (defined $seen{$_->{host}.$_->{port}}) {
			$seen{$_->{host}.$_->{port}} = 1;
			push @{$new}, {
				host => $_->{host},
				port => $_->{port},
				pw => $_->{pw}
			};
		}
	}
	$self->{favorites} = $new;
}

# Save our entries to file
sub save {
	my $self = shift;
	my $handle;
	return 0 unless open($handle, '>'.$self->{filename});
	print $handle $_->{host}.':'.$_->{port}.':'.$_->{pw}."\n" foreach (@{$self->get()});
	close $handle;
	1;
}

# Load our file
sub load {
	my $self = shift;
	my $handle;
	return 0 unless open($handle, 'favs.txt');
	splice @{$self->{favorites}};
	while (<$handle>) {
		if (m/^(?!\#)([^:]+):(\d+):([^\$]+)$/) {
			my ($host, $port, $pw) = ($1, $2, $3);
			$host =~ s/^\s+|\s+$//g;
			$port =~ s/^\s+|\s+$//g;
			$pw =~ s/^\s+|\s+$//g;
			push @{$self->{favorites}}, {
				host => $host,
				port => $port,
				pw => $pw
			};
		}
	}
	close $handle;
	1;
}

1;
