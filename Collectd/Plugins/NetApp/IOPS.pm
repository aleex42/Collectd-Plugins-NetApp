# --
# NetApp/IOPS.pm - Collectd Perl Plugin for NetApp Storage Systems (IOPS Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2015 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::IOPS;

use base 'Exporter';
our @EXPORT = qw(iops_module);

no warnings 'experimental::given';
no warnings 'experimental::when';

use strict;
use warnings;

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Data::Dumper;

use Config::Simple;

sub iops_module {

    my %nodes;
    my $hostname = shift;

    my $iterator = NaElement->new("system-node-get-iter");
    my $tag_elem = NaElement->new("tag");
    $iterator->child_add($tag_elem);

    my $next = "";

    while(defined($next)){
        unless($next eq ""){
            $tag_elem->set_content($next);    
        }

        $iterator->child_add_string("max-records", 100);
        my $output = connect_filer($hostname)->invoke_elem($iterator);

        my $heads = $output->child_get("attributes-list");
        if($heads){
            my @result = $heads->children_get();

            foreach my $head (@result){
                my $node_name = $head->child_get_string("node");
                my $node_uuid = $head->child_get_string("node-uuid");
                $nodes{$node_uuid} = $node_name;
            }
            $next = $output->child_get_string("next-tag");
        }

        my $in = NaElement->new("perf-object-get-instances");
        $in->child_add_string("objectname","system:node");
        my $xi1 = NaElement->new("instance-uuids");
        $in->child_add($xi1);
        foreach (keys %nodes){
            $xi1->child_add_string('instance-uuid',$_);
        }
        my $counters = NaElement->new("counters");
        $in->child_add($counters);
        $counters->child_add_string("counter","other_ops");
        $counters->child_add_string("counter","read_ops");
        $counters->child_add_string("counter","system_ops");
        $counters->child_add_string("counter","write_ops");

        my $xo = connect_filer($hostname)->invoke_elem($in);

        my $instances = $xo->child_get("instances");
        if($instances){

            my @instance_data = $instances->children_get("instance-data");

            my %total_count;

            foreach my $node (@instance_data){

                my $node_name = $node->child_get_string("name");

                my $counters = $node->child_get("counters");
                if($counters){

                    my @counter_result = $counters->children_get();

                    foreach my $counter (@counter_result){

                        my $name = $counter->child_get_string("name");
                        my $value = $counter->child_get_string("value");

                        my $plugin;

                        given($name) {
                            when (['cifs_ops', 'fcp_ops', 'iscsi_ops']) { $plugin = "iops_protocol"; }
                            when (['other_ops', 'read_ops', 'system_ops', 'write_ops']) { $plugin = "iops_total"; }
                            default { next; }
                        }

                        if($total_count{$name}){
                            $total_count{$name} += $value;
                        } else {
                            $total_count{$name} = $value;
                        }

                        plugin_dispatch_values({
                                plugin => $plugin,
                                plugin_instance => $node_name,
                                type => 'disk_ops_complex',
                                type_instance => $name,
                                values => [$value],
                                interval => '30',
                                host => $hostname
                                });
                    }
                }
            }

            foreach (keys %total_count){

                my $plugin;

                given($_) {
                    when (['cifs_ops', 'fcp_ops', 'iscsi_ops', 'nfs_ops']) { $plugin = "iops_protocol"; }
                    when (['other_ops', 'read_ops', 'system_ops', 'write_ops']) { $plugin = "iops_total"; }
                    default { next; }
                }

                plugin_dispatch_values({
                        plugin => $plugin,
                        plugin_instance => $hostname,
                        type => 'disk_ops_complex',
                        type_instance => $_,
                        values => [$total_count{$_}],
                        interval => '30',
                        host => $hostname
                        });
            }
        }
    }

    my @protocols = ('nfsv3', 'nfsv4', 'cifs', 'iscsi', 'fcp');
    
    foreach my $proto (@protocols){
    
        my $in = NaElement->new("perf-object-get-instances"); # werte holen
        $in->child_add_string("objectname","$proto:node");
    
        my $xi1 = NaElement->new("instance-uuids");
        $in->child_add($xi1);
        foreach (keys %nodes){
            $xi1->child_add_string('instance-uuid',$_);
        }
        my $counters = NaElement->new("counters");
        $in->child_add($counters);
        $counters->child_add_string("counter","${proto}_ops");
    
        my $xo = connect_filer($hostname)->invoke_elem($in);
    
        my %node_sum;
    
        my $instances = $xo->child_get("instances");
        if($instances){
    
            my @instance_data = $instances->children_get("instance-data");
    
            foreach my $node (@instance_data){
    
                my $node_name = $node->child_get_string("name");
    
                my $counters = $node->child_get("counters");
                if($counters){
    
                    my @counter_result = $counters->children_get();
    
                    foreach my $counter (@counter_result){
    
                        my $name = $counter->child_get_string("name");
                        my $value = $counter->child_get_string("value");
   
                        plugin_dispatch_values({
                            plugin => "iops_protocol",
                            plugin_instance => $node_name,
                            type => 'disk_ops_complex',
                            type_instance => "${proto}_ops",
                            values => [$value],
                            interval => '30',
                            host => $hostname,
                        });
 
                        $node_sum{$proto} += $value;
                    }
                }
            }
            plugin_dispatch_values({
                    plugin => "iops_protocol",
                    plugin_instance => $hostname,
                    type => 'disk_ops_complex',
                    type_instance => "${proto}_ops",
                    values => [$node_sum{$proto}],
                    interval => '30',
                    host => $hostname,
            });
        }
    }

    my @qos_groups;

    $iterator = NaElement->new("perf-object-instance-list-info-iter");
    $tag_elem = NaElement->new("tag");
    $iterator->child_add($tag_elem);
    $iterator->child_add_string("objectname","policy_group");
    
    $next = "";
    
    while(defined($next)){
        unless($next eq ""){
            $tag_elem->set_content($next);
        }
    
        $iterator->child_add_string("max-records", 100);
        my $output = connect_filer($hostname)->invoke_elem($iterator);
    
        my $heads = $output->child_get("attributes-list");
        my @result = $heads->children_get();
    
        foreach my $pg (@result){
            push(@qos_groups, $pg->child_get_string("node-uuid"));
        }
        $next = $output->child_get_string("next-tag");
    }
    
    my $in = NaElement->new("perf-object-get-instances"); 
    $in->child_add_string("objectname","policy_group");
    my $xi1 = NaElement->new("instance-uuids");
    $in->child_add($xi1);
    foreach (@qos_groups){
        $xi1->child_add_string('instance-uuid',$_);
    }
    my $counters = NaElement->new("counters");
    $in->child_add($counters);
    $counters->child_add_string("counter","total_ops");

    my $xo = connect_filer($hostname)->invoke_elem($in);
    
    my $instances = $xo->child_get("instances");
    if($instances){
    
        my @instance_data = $instances->children_get("instance-data");
    
        foreach my $group (@instance_data){
    
            my $policy_name = $group->child_get_string("name");
    
            my $counters = $group->child_get("counters");
            if($counters){
    
                my @counter_result = $counters->children_get();
    
                foreach my $counter (@counter_result){
    
                    my $name = $counter->child_get_string("name");
                    my $value = $counter->child_get_string("value");
    
                    plugin_dispatch_values({
                        plugin => 'iops_policy',
                        type => 'operations',
                        type_instance => $policy_name,
                        values => [$value],
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
