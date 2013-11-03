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

use Collectd::Plugins::NetApp::CPU qw(cdot_cpu);

use Data::Dumper;

use Collectd qw( :all );
use Config::Simple;

my $plugin_name = "NetApp";

my %hosts = ();

plugin_register(TYPE_CONFIG, $plugin_name, 'my_config');
plugin_register(TYPE_READ, $plugin_name, 'my_get');
plugin_register(TYPE_INIT, $plugin_name, 'my_init');

sub my_log {
        plugin_log shift @_, join " ", "$plugin_name", @_;
}

sub my_init {
    1;
}

sub my_config {

    my $config = shift;
    my @children = @{$config -> {children} };

    for my $host (@children){

        my $hostname;

        if($host->{key}){
            if($host->{key} eq "Host"){
                $hostname = $host->{values}->[0];
                for my $child (@{ $host->{children} }) {
                    if($child->{key} eq "Modules"){
                        my $modules = $child->{values};
                        my $count = scalar @{ $modules };
                        for my $i (0 ... $count-1){
                            push (@{$hosts{$hostname}},$modules->[$i]);
                        }
                    }
                }
            }
        }
    }
}

sub my_get {

    foreach my $hostname (keys %hosts){

# TODO: Switch for different modules

            my $cpu_result = cdot_cpu($hostname);

            foreach my $node (keys %$cpu_result){

                my $node_value = $cpu_result->{$node};

                plugin_dispatch_values({
                        plugin => 'cpu',
                        plugin_instance => $node,
                        type => 'cpu',
                        values => [$node_value],
                        interval => '30',
                        host => $hostname,
                        });
        }
    }

    return 1;

}

1;

