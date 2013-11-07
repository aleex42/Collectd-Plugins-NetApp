# --
# NetApp/NIC.pm - Collectd Perl Plugin for NetApp Storage Systems (NIC Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::NIC;

use base 'Exporter';
our @EXPORT = qw(nic_module);

use strict;
use warnings;

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
use NaServer;
use NaElement;

use Data::Dumper;
use Config::Simple;

sub cdot_nic {

    my $hostname = shift;
    my %cpu_return;

    return \%cpu_return;

}

sub smode_nic {

    my $hostname = shift;
    my %nic_return;

    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","ifnet");
    my $counters = NaElement->new("counters");    
    $counters->child_add_string("counter","recv_data");
    $counters->child_add_string("counter","send_data");
    $in->child_add($counters);

    my $out = connect_filer($hostname)->invoke_elem($in);

    my $instances_list = $out->child_get("instances");
    my @instances = $instances_list->children_get();

    foreach my $interface (@instances){

        my $int_name = $interface->child_get_string("name");

        my $counters_list = $interface->child_get("counters");
        my @counters = $counters_list->children_get();

        my %values = (recv_data => undef, send_data => undef);

        foreach my $counter (@counters){

            my $key = $counter->child_get_string("name");
            if(exists $values{$key}){
                $values{$key} = $counter->child_get_string("value");
            }
        }

        $nic_return{$int_name} = [ $values{recv_data}, $values{send_data} ];
    }

    return \%nic_return;

}

sub nic_module {

    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $cpu_result = cdot_cpu($hostname);

            foreach my $node (keys %$cpu_result){

                my $node_value = $cpu_result->{$node};

                plugin_dispatch_values({
                        plugin => 'cpu',
                        plugin_instance => $node,
                        type => 'cpu',
                        type_instance => 'cpu_busy',
                        values => [$node_value],
                        interval => '30',
                        host => $hostname,
                        });
            }
        }

        default {

            my $nic_result = smode_nic($hostname);

            if($nic_result){

                foreach my $nic (keys %$nic_result){

                    my $nic_value_ref = $nic_result->{$nic};
                    my @nic_value = @{ $nic_value_ref };

                plugin_dispatch_values({
                    plugin => 'interface',
                    plugin_instance => $nic,
                    type => 'if_octets',
#                    type_instance => '',
                    values => [$nic_value[0], $nic_value[1]],
                    interval => '30',
                    host => $hostname,
                    });
                }
            }
        }
    }

    return 1;
}

1;

