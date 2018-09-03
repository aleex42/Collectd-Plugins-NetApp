# --
# NetApp/NACommon.pm - Collectd Perl Plugin for NetApp Storage Systems (NetApp Common Functions)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::NACommon;

use base 'Exporter';
our @EXPORT = qw(connect_filer);

use strict;
use warnings;

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub connect_filer {

    my $hostname = shift;

    my $ConfigFile = "/etc/collectd/netapp.ini";
    my $cfg = new Config::Simple($ConfigFile);
    my %Config = $cfg->vars();

    my ($username, $password);

    if($Config{ $hostname . '.Username'}){
        $username = $Config{ $hostname . '.Username'};
    } else { 
        $username = $Config{ 'Default.Username'};
    }

    if($Config{ $hostname . '.Password'}){
        $password = $Config{ $hostname . '.Password'};
    } else {
        $password = $Config{ 'Default.Password'}
    }

    my $s = NaServer->new( $hostname, 1, 3 );
    $s->set_style('LOGIN');
    $s->set_timeout(10);
    $s->set_admin_user( $username, $password );
    $s->set_transport_type('HTTPS');

    return $s;
}

1;

