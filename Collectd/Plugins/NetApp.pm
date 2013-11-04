# --
# NetApp.pm - Collectd Perl Plugin for NetApp Storage Systems
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp;

use strict;
use warnings;

use Collectd::Plugins::NetApp::CPU qw(cpu_module);

use feature qw/switch/;

use Data::Dumper;

use Collectd qw( :all );
use Config::Simple;

my $ConfigFile = "/etc/collectd/netapp.ini";
my $cfg = new Config::Simple($ConfigFile);
my %Config = $cfg->vars();

my $plugin_name = "NetApp";

plugin_register(TYPE_READ, $plugin_name, 'my_get');
plugin_register(TYPE_INIT, $plugin_name, 'my_init');

sub my_log {
        plugin_log shift @_, join " ", "$plugin_name", @_;
}

sub my_init {
    1;
}

sub my_get {

    foreach my $hostname (keys %{ $cfg->{_DATA}}){

        my $filer_os = $Config{ $hostname . '.Mode'};
        my $modules = $Config{ $hostname . '.Modules'};

        my @modules_array = @{ $modules };

        foreach my $module (@modules_array){

            given($module){

                when("CPU"){
                    cpu_module($hostname, $filer_os);
                }

                when("DF"){

                    plugin_dispatch_values({
                            plugin => 'df',
                            plugin_instance => "test-01",
                            type => 'df',
                            type_instance => 'test_instance',
                            values => ['10123123123', '43523424343'],
                            interval => '30',
                            host => $hostname,
                            });
                }

                default {
# nothing
                }
            }
        }
    }

return 1;

}

1;

