# --
# NetApp/CPU.pm - Collectd Perl Plugin for NetApp Storage Systems (CPU Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::CPU;

use base 'Exporter';
our @EXPORT = qw(cpu_module);

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

sub cdot_cpu {

    my $hostname = shift;
    my %cpu_return;

    my $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "system");

    if($output){
        my $nodes = $output->child_get("attributes-list");

        if($nodes){
            my @result = $nodes->children_get();

            foreach my $node (@result){

                my $node_uuid = $node->child_get_string("uuid");
                my @node = split(/:/,$node_uuid);
                my $node_name = $node[0];

                my $api = new NaElement('perf-object-get-instances');

                my $xi = new NaElement('counters');
                $api->child_add($xi);
                $xi->child_add_string('counter','cpu_busy');

                my $xi1 = new NaElement('instance-uuids');
                $api->child_add($xi1);

                $xi1->child_add_string('instance-uuid',$node_uuid);
                $api->child_add_string('objectname','system');

                my $xo = connect_filer($hostname)->invoke_elem($api);

                my $instances = $xo->child_get("instances");
                my $instance_data = $instances->child_get("instance-data");
                my $counters = $instance_data->child_get("counters");
                my $counter_data = $counters->child_get("counter-data");

                my $rounded_busy = sprintf("%.0f", $counter_data->child_get_int("value")/10000);

                $cpu_return{$node_name} = $rounded_busy;
            }
        }

    }

    return \%cpu_return;

}

sub smode_cpu {

    my $hostname = shift;

    my $api = new NaElement('perf-object-get-instances');

    my $xi = new NaElement('counters');
    $api->child_add($xi);
    $xi->child_add_string('counter','cpu_busy');
    $api->child_add_string('objectname','system');
    my $xo = connect_filer($hostname)->invoke_elem($api);

    my $instances = $xo->child_get("instances");
    
    if($instances){
        my $instance_data = $instances->child_get("instance-data");
        my $counters = $instance_data->child_get("counters");
        my $counter_data = $counters->child_get("counter-data");

        my $rounded_busy = sprintf("%.0f", $counter_data->child_get_int("value")/10000);
    
        return $rounded_busy;

    } else {
        return undef;
    }
}

sub cpu_module {

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
                        type_instance => 'cpu_busy_new',
                        values => [$node_value],
                        interval => '30',
                        host => $hostname,
                        });
            }
        }

        default {

            my $cpu_result = smode_cpu($hostname);

            if($cpu_result){

                plugin_dispatch_values({
                    plugin => 'cpu',
                    plugin_instance => 'total',
                    type => 'cpu',
                    type_instance => 'cpu_busy_new',
                    values => [$cpu_result],
                    interval => '30',
                    host => $hostname,
                    });
            }
        }
    }

    return 1;
}

1;

