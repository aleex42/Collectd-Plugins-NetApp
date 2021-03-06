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

use Data::Dumper;

use base 'Exporter';
our @EXPORT = qw(cpu_module);

use strict;
use warnings;
no warnings "experimental";

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub cpu_module {

    my $hostname = shift;
    #my %cpu_return;
    my $starttime = time();

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "processor:node");
    };
    plugin_log(LOG_INFO, "*DEBUG* connect fail cdot_cpu: $@") if $@;

    if($output){
        my $nodes = $output->child_get("attributes-list");

        if($nodes){
            my @result = $nodes->children_get();

            foreach my $node (@result){

                my $node_uuid = $node->child_get_string("uuid");
                my $node_name = $node->child_get_string("name");
                my @node = split(/:/,$node_name);
                $node_name = $node[0];

                my $api = new NaElement('perf-object-get-instances');

                my $xi = new NaElement('counters');
                $api->child_add($xi);
                $xi->child_add_string('counter','processor_busy');
                $xi->child_add_string('counter','processor_elapsed_time');

                my $xi1 = new NaElement('instance-uuids');
                $api->child_add($xi1);

                $xi1->child_add_string('instance-uuid',$node_uuid);
                $api->child_add_string('objectname','processor:node');

                my $xo;
                eval {
                    $xo = connect_filer($hostname)->invoke_elem($api);
                };
                plugin_log(LOG_INFO, "*DEBUG* connect filer: $@") if $@;

                my $instances = $xo->child_get("instances");

                if($instances){
                    my $instance_data = $instances->child_get("instance-data");
                    my $counters = $instance_data->child_get("counters");

                    if($counters){

                        my @result = $counters->children_get();

                        my %values = (processor_busy => undef, processor_elapsed_time => undef);

                        foreach my $counter (@result){
                            my $key = $counter->child_get_string("name");
                            if(exists $values{$key}){
                                $values{$key} = $counter->child_get_string("value");
                            }
                        }

                        my $busy = $values{processor_busy};
                        my $time = $values{processor_elapsed_time};

                        plugin_dispatch_values({
                            plugin => 'cpu',
                            type => 'netapp_cpu',
                            type_instance => $node_name,
                            values => [$time, $busy],
                            interval => '30',
                            host => $hostname,
                            time => $starttime,
                        });

                    }
                }
            }
        }
    }
    return 1;
}

1;


