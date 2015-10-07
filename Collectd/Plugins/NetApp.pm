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

use threads;

use Collectd::Plugins::NetApp::CPU qw(cpu_module);
use Collectd::Plugins::NetApp::Volume qw(volume_module);
use Collectd::Plugins::NetApp::Aggr qw(aggr_module);
use Collectd::Plugins::NetApp::NIC qw(nic_module);
use Collectd::Plugins::NetApp::Disk qw(disk_module);
use Collectd::Plugins::NetApp::Flash qw(flash_module);

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
plugin_register(TYPE_CONFIG, $plugin_name, 'my_config');

sub my_config {
    1;
}

sub my_log {
#        plugin_log shift @_, join " ", "$plugin_name", @_;
}

sub my_init {
    1;
}

sub thread_func {

    my $hostname = shift;
    $SIG{'KILL'} = sub { plugin_log("LOG_INFO", "*TIMEOUT* $hostname GOT KILLED") };
    
    my $filer_os = $Config{ $hostname . '.Mode'};
    my $modules = $Config{ $hostname . '.Modules'};

    if($modules){

        my @modules_array = @{ $modules };

        foreach my $module (@modules_array){

            given($module){

                when("CPU"){
                    eval {
                        cpu_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* cpu_module: $@") if $@;
                }

                when("Aggr"){
                    eval {
                        aggr_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* aggr_module: $@") if $@;

                }

                when("Volume"){
                    eval {
                        volume_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* volume_module: $@") if $@;
                }

                when("NIC"){
                    eval {
                        nic_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* nic_module: $@") if $@;
                }

                when("Disk"){
                    eval {
                        disk_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* disk_module: $@") if $@;
                }

                when("Flash"){
                    eval {
                        flash_module($hostname, $filer_os);
                    };
                    plugin_log("LOG_DEBUG", "*DEBUG* flash_module: $@") if $@;
                }

                default {
                # nothing
                }
            }
        }
    }
}

sub my_get {

    plugin_log("LOG_DEBUG", "*DEBUG* started my get");

    my @hosts = keys %{ $cfg->{_DATA}};

    my @threads = ();

    foreach my $host (@hosts)  {
       push (@threads, threads->create (\&thread_func, $host));
       plugin_log("LOG_DEBUG", "*DEBUG* new thread $host");
    }

    sleep 30;
    plugin_log("LOG_DEBUG", "*DEBUG* READY ". threads->list(threads::joinable));
    foreach (threads->list(threads::joinable)) {
        $_->join(); # blocks until this thread exits
    }

    plugin_log("LOG_DEBUG", "*DEBUG* RUNNING ". threads->list(threads::running));
    foreach (threads->list(threads::running)) {
        $_->kill('KILL');
        $_->detach();
    }

    plugin_log("LOG_DEBUG", "*DEBUG* return 1");
    return 1;
}

1;

