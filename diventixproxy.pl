#!/usr/bin/perl
=pod
The MIT License (MIT)

Copyright (c) 2014 Håkon Nessjøen <haakon@trippelm.no>
Copyright (c) 2014 Trippel-M Levende Bilder AS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
=cut

use IO::Socket::INET;
use IO::Select;
use Storable 'dclone';
use Curses;
use Curses::UI::Common;
use Curses::UI::Window;
use Curses::UI;
use Curses::UI::Dialog::Basic;
use Storable;
use strict;

$ENV{ESCDELAY} = 200;

sub WARN_handler {
    my($signal) = @_;
    sendToLogfile("WARN: $signal");
}

sub DIE_handler {
    my($signal) = @_;
    sendToLogfile("DIE: $signal");
}

sub sendToLogfile {
    my(@array) = @_;
    open(LOGFILE, ">>program.log");
    print LOGFILE (@array);
    close(LOGFILE);
}

$SIG{__WARN__} = 'WARN_handler';
$SIG{__DIE__}  = 'DIE_handler';

my %defines = (
	'PE_INPUTNUM' => 'IN',
	'PE_SOURCENUM' => 'IS',
#	'PE_ID' => 'pI',
#	'PE_NEW_ID' => 'pN',
	'PE_POS_H' => 'pH',
	'PE_POS_V' => 'pV',
	'PE_SIZE_H' => 'pW',
	'PE_SIZE_V' => 'pS',
	'PE_CROP_WIN_POS_H' => 'CH',
	'PE_CROP_WIN_POS_V' => 'CV',
	'PE_CROP_WIN_SIZE_H' => 'CW',
	'PE_CROP_WIN_SIZE_V' => 'CS',
	'PE_ALPHA' => 'pA',
	'PE_BORDER_STYLE' => 'bS',
	'PE_BORDER_COLOR' => 'bC',
	'PE_BORDER_ALPHA' => 'bA',
	'PE_BORDER_SIZE_H' => 'bH',
	'PE_BORDER_SIZE_V' => 'bV',
	'PE_BORDER_SHADOW_POS' => 'bP',
	'PE_OPENING_TRANSITION' => 'oT',
	'PE_OPENING_TRANSITION_WAY' => 'oW',
	'PE_OPENING_DURATION' => 'oD',
	'PE_CLOSING_TRANSITION' => 'cT',
	'PE_CLOSING_TRANSITION_WAY' => 'cW',
	'PE_CLOSING_DURATION' => 'cD',
	'PE_FREEZE_INPUT' => 'pZ'
);

my $sel = IO::Select->new();

if (scalar @ARGV < 1) {
	print STDERR "Missing parameter: IP and/or port of Di Ventix II\n";
	print STDERR "Usage: $0 <ip> [port]\n\n";
	exit 1;
}

my $ip = $ARGV[0];
my $port = $ARGV[1] || 10500;

my $sock = IO::Socket::INET->new(
	PeerAddr => $ip,
	PeerPort => $port,
	Proto    => 'tcp'
) or die $!;

my $listen = IO::Socket::INET->new(
	LocalPort => '10500',
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1,
) or die $!;

my %states = {};
my %presets = {};

if (-f 'presets.dat') {
	%presets = %{retrieve('presets.dat')};
}
$sock->send("1#");

$sel->add($sock);
$sel->add(\*STDIN);
$sel->add($listen);

use Data::Dumper;

my $cui = new Curses::UI( -color_support => 1, -read_timeout => 0, -mouse_support => 0 );
my $win = $cui->add(
	'win1', 'Window',
	-border => 1,
	-y    => 0,
	-title => 'Di-Ventix II - Preset supersystem',
	-padbottom => 1,
	-paddingspaces => 1,
	-bfg => 'yellow',
	-tfg => 'yellow',
);
my $statuswin = $cui->add(
	'statuswin', 'Window',
	-y => -1,
	-height => 1
);
my $statuslabel = $statuswin->add(
	'status', 'Label',
	-reverse => 1,
	-width => -1,
	-paddingspaces => 1,
	-height => 1,
	-text => ''
	);

sub exit_dialog()
{
	my $return = $cui->dialog(
		-message   => "Do you really want to quit?",
		-title     => "Are you sure???", 
		-buttons   => ['yes', 'no'],
	);

	exit(0) if $return;
}

my $listbox;
$listbox = $win->add(
        'mylistbox', 'Listbox',
	-x => 1,
	-y => 13,
	-title => 'Presets',
	-border => 1,
	-height => 13,
	-width => 26,
	-htmltext => 1,
	-onchange => sub {
		doload($listbox->get_active_value());
	}
);
$listbox->values(keys %presets);


my $buttons = $win->add(
        'mybuttons', 'Buttonbox',
	-width => 18,
        -buttons   => [
            { 
              -label => '< Save >',
              -value => 1,
              -shortcut => 'S',
	      -onpress => sub {
		dosave($listbox->get_active_value());
	      }
            },{ 
              -label => '< New >',
              -value => 2,
              -shortcut => 'N',
	      -onpress => sub {
	      	$presets{'New preset'} = {};
		$listbox->insert_at($listbox->get_active_id(), 'New preset');
		$listbox->draw();
	      }
	    }
        ],
	-y => 27,
	-x => 1
);

  my $takebutton = $win->add(
  	'takebutton', 'Buttonbox',
	-width => 8,
	-y => 27,
	-x => 20,
	-buttons => [{
		-label => '< Take >',
		-shortcut => 'T',
		-onpress => sub {
			print $sock "1TK";
		}
	}]
  );

my $textwin = $win->add( 
	'mytextviewer', 'TextViewer',
	-title => "Statuslog",
	-text => "",
	-border => 1,
	-y => 13,
	-x => 30,
);

# Tester preset navngivning :)
$listbox->set_binding(sub {
	my ($ref, $key) = @_;
	my $data = $cui->question(-question => 'What is the new name?', -answer => $key);
	if ($data ne "") {
		$presets{$data} = $presets{$listbox->get_active_value()};
		delete $presets{$listbox->get_active_value()};
		$listbox->values(keys %presets);
		$listbox->clear_selection();

	}
}, qw{ a b c d e f g h i j k l m n o p q r s t u v w x y z A B C D E F G H I J K L M N O P Q R S T U V W X Y Z });

my $donesaving  = 0;
my $doneloading = 0;
my @inputs;
my @sdiinputs;
my @dviinputs;
my @ainputs;
for my $i (0..7) {
	$inputs[$i] = $win->add(
		'input' . $i, 'Label',
		-text => $i+1,
		-bold => 1,
		-y => 8,
		-x => 3 + ($i * 14),
		-width => 6,
		-textalignment => 'middle'
	);
	$ainputs[$i] = $win->add(
		'ainput' . $i, 'Label',
		-text => 'Analog',
		-y => 9,
		-x => 3 + ($i * 14),
		-width => 6,
		-textalignment => 'middle'
	);
	if ($i < 4) {
		$dviinputs[$i] = $win->add(
			'dviinput' . $i, 'Label',
			-text => 'DVI',
			-y => 10,
			-x => 3 + ($i * 14),
			-width => 6,
			-textalignment => 'middle'
		);
		$sdiinputs[$i] = $win->add(
			'sdiinput' . $i, 'Label',
			-text => 'SDI',
			-y => 11,
			-x => 3 + ($i * 14),
			-textalignment => 'middle',
			-width => 6,
		);
	}
}
$textwin->focusable(0);

$cui->set_binding( sub {
	print $sock "1TK";
}, "\n", "\r", "ENTER", "enter");
$cui->set_binding( \&exit_dialog , "\cC");
$cui->set_binding( \&exit_dialog , "\cQ");
$cui->set_binding( sub {
	doload($listbox->get_active_value());
}, "\cL");
$cui->set_binding(sub {
	dosave($listbox->get_active_value());
}, "\cS");
$cui->set_binding( sub {
	print $sock "1TK";
}, "\cT");
$cui->set_binding( sub {
	$listbox->insert_at($listbox->get_active_id(), 'New preset');
}, "\cN");
$cui->focus();
$win->focus();
$listbox->focus();
$listbox->draw();
$cui->draw();
$cui->{-read_timeout} = 0;

{
	no warnings "redefine";
	no strict 'refs';

	my $modalfocus =  \&Curses::UI::Widget::modalfocus;
	sub Curses::UI::Widget::modalfocus ()
	{
	    my $this = shift;

	    # "Fake" focus for this object.
	    $this->{-has_modal_focus} = 1;
	    $this->focus;
	    $this->draw;

	    # Event loop ((too?) much like Curses::UI->mainloop)
	    while ( $this->{-has_modal_focus} ) {
		one_loop($this);
	    }

	    $this->{-focus} = 0;
	    $this->{-has_modal_focus} = 0;

	    return $this;
	}
	*{"Curses::UI::Widget::modalfocus"} = $modalfocus;
}

sub doload {
	my $id = shift();
	if (defined $presets{$id}) {
		status('Loading preset');
		$doneloading = 10;
		my %preset = %{$presets{$id}};
		$textwin->text("Loading preset $id\n".$textwin->text());
		print $sock "1NP";
		$textwin->text("Sending:1NP\n".$textwin->text());
		print $sock "0IU";
		foreach my $layer (keys %preset) {
			#print "Layer $layer:\n";
			if (defined $preset{$layer}) {
				foreach my $setting (keys $preset{$layer}) {
					#print "\t$setting = ".$preset{$layer}{$setting}." or ".$states{$layer}{$setting}."\n";
					if ($preset{$layer}{$setting} ne $states{$layer}{$setting}) {
						$textwin->text("Sending:1,$layer,".$preset{$layer}{$setting}.$defines{$setting}."\n".$textwin->text());
						$textwin->draw();
						print $sock "1,$layer,".$preset{$layer}{$setting}.$defines{$setting};
						#print "$layer,1,".$preset{$layer}{$setting}.$defines{$setting}."\n";
					}
				}
			}
		}
		print $sock "1IU";
	}
}

sub dosave {
	status('Saving preset');
	$donesaving = 30;
	$presets{shift()} = dclone(\%states);
	store \%presets, 'presets.dat';
}
my @clients;
my $dialog;
my @statuses;

sub status {
	my $index = 0;
	my $text = shift;
	$index++ until $statuses[$index] eq $text || $index > scalar(@statuses);
	push(@statuses, $text) if $index > scalar(@statuses);
	$statuslabel->text($statuses[$#statuses]);
	$statuslabel->draw();
}
sub nostatus {
	my $text = shift();
	my $index = 0;
	$index++ until $statuses[$index] eq $text || $index > scalar(@statuses);
	splice(@statuses, $index, 1) if ($index < scalar(@statuses));
	$statuslabel->text($statuses[$#statuses]);
	$statuslabel->draw();
}

status('Idle');

my $logo = $win->add(
	'logo', 'Label',
	-text => '________  .______   ____             __  .__       .___.___ 
\______ \ |__\   \ /   /____   _____/  |_|__|__  __|   |   |
 |    |  \|  |\   Y   // __ \ /    \   __\  \  \/  /   |   |
 |    `   \  | \     /\  ___/|   |  \  | |  |>    <|   |   |
/_______  /__|  \___/  \___  >___|  /__| |__/__/\_ \___|___|
        \/                 \/     \/              \/        ',
	-y => 1,
	-x => 1,
	-width => 61,
	-height => 6,
	-border => 0
);
$textwin->text('
Shortcuts:
  <Enter>  Load current preset
  ^S       Save to current preset
  ^D       Delete preset
  ^N       New preset
  ^Q       Exit

Connecting...');

sub one_loop {
	my $modal_element = shift();
	my $data;

	$cui->do_one_event($modal_element);

	my @list = $sel->can_read(.1);
	if (@list == 0 && $doneloading > 0) {
		if (--$doneloading == 0) {
			nostatus('Loading preset');
		}
	}
	if ($donesaving > 0) {
		if (--$donesaving == 0) {
			nostatus('Saving preset');
		}
	}

	foreach my $s (@list) {
		if ($s == $listen) {
			my $client = $listen->accept();
			$sel->add($client);
			push @clients, $client;
		}
		out:
		for my $client (@clients) {
			if ($s == $client) {
				$client->recv($data, 2048);
				unless ($data ne "") {
					$textwin->text("Client disconnected\n".$textwin->text());
					$sel->remove($client);
					my $index = 0;
					$index++ until $clients[$index] == $client || $index > scalar(@clients);
					splice(@clients, $index, 1) if ($index < scalar(@clients));
					last out;
				};
				$textwin->text("Client to server: $data\n".$textwin->text()) if ($data ne '?');
				$textwin->draw();
				$sock->write($data);
			}
		}
		if ($s == $sock) {
			my $indata;
			sysread $sock, $indata, 10241024;
			foreach my $client (@clients) {
				$client->send($indata);
			}
			while ($indata =~ m/([^\r\n]+)(\s*)/gs) {
				my $data = $1;
				my $crlf = $2;
				if ($data =~ m/^#1/) {
					my $text = $win->getobj('mydialog') || $win->add(
						'mydialog', 'TextViewer',
						    -text   => 'Connecting, loading initial status',
						    -x => 1,
						    -y => 20,
						    -wrapping => 1,
						    -width => 26,
						    -height => 40
					);
					$text->focusable(0);
					$text->draw();
					$win->draw();
					status('Connected, receiving initial data');
				}
				if ($data =~ m/^#0/) {
					nostatus('Connected, receiving initial data');
					$win->delete('mydialog');
					$dialog = undef;
					$buttons->focus();
					$win->draw();
				}
				if ($data =~ m/^sD(\d+),(\d+),(\d+)/) {
					my ($input, $type, $value) = ($1,$2,$3);

					if ($type eq '0') {
						$ainputs[int($input)]->set_color_bg(int($value) > 2 ? 'green' : 'black');
						$ainputs[int($input)]->draw();
					} elsif ($type eq '1') {
						if (int($input) < 4) {
							$dviinputs[int($input)]->set_color_bg(int($value) > 2 ? 'green' : 'black');
							$dviinputs[int($input)]->draw();
						}
					} elsif ($type eq '2') {
						if (int($input) < 4) {
							$sdiinputs[int($input)]->set_color_bg(int($value) > 2 ? 'green' : 'black');
							$sdiinputs[int($input)]->draw();
						}
					}
				}
				if ($data =~ m/^IP(\d+),(\d+),(\d+)/) {
					my ($preset, $input, $type) = ($1, $2, $3);

					next if ($preset ne '1');
					$ainputs[int($input)]->set_color_fg('white');
					if (int($input) < 4) {
						$dviinputs[int($input)]->set_color_fg('white');
						$sdiinputs[int($input)]->set_color_fg('white');
					}
					if ($type eq '0') {
						$ainputs[int($input)]->set_color_fg('blue');
						$ainputs[int($input)]->bold(1);
					} elsif ($type eq '1') {
						if (int($input) < 4) {
							$dviinputs[int($input)]->set_color_fg('blue');
							$dviinputs[int($input)]->bold(1);
						}
					} elsif ($type eq '2') {
						if (int($input) < 4) {
							$sdiinputs[int($input)]->set_color_fg('blue');
							$sdiinputs[int($input)]->bold(1);
						}
					}
					$ainputs[int($input)]->draw();
					if (int($input) < 4) {
						$sdiinputs[int($input)]->draw();
						$dviinputs[int($input)]->draw();
					}
				}
				if ($data =~ m/^TA(\d)/) {
					$takebutton->lose_focus() if $1 eq '0';
					$takebutton->focusable(int($1));
					$takebutton->draw();
				}
				if ($data =~ m/^TK(\d)/) {
					status('Taking...') if ($1 eq '1');
					nostatus('Taking...') if ($1 eq '0');
					$takebutton->set_color_fg($1 eq '1' ? 'red' : 'white');
					$takebutton->draw();
				}
				foreach my $key (keys %defines) {
					my $search = $defines{$key};

					if ($data =~ m/^$search(.+?)\s*$/) {
						my ($preset, $layer, $value) = split/,/,$1;
						if ($preset eq '1') {
							$states{$layer}{$key} = $value;
							my @layers = ('BG', 'A', 'B', 'C', 'D', 'Logo A', 'Logo B', 'Frame mask');
							$textwin->text("[Layer ".$layers[int($layer)]."] $key = $value\n".$textwin->text());
							$textwin->draw();
						}
						#print "Got: [$layer] $key = $value\n" if ($preset eq '1'); # Preview
					}
				}
			}
		}
	}


}

while (1) {
	one_loop();
}

