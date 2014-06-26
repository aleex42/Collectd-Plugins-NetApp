# --
# NetApp/Aggr.pm - Collectd Perl Plugin for NetApp Storage Systems (Aggr Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::Aggr;

use base 'Exporter';
our @EXPORT = qw(aggr_module);

use strict;
use warnings;

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub smode_aggr_df {

    my $hostname = shift;
    my (%df_return, $used_space, $total_space, $total_transfers);

    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","aggregate");
    my $counters = NaElement->new("counters");
    $counters->child_add_string("counter","wv_fsinfo_blks_total");
    $counters->child_add_string("counter","wv_fsinfo_blks_used");
    $counters->child_add_string("counter","wv_fsinfo_blks_reserve");
    $counters->child_add_string("counter","wv_fsinfo_blks_snap_reserve_pct");
    $counters->child_add_string("counter","user_reads");
    $counters->child_add_string("counter","user_writes");
    $in->child_add($counters);
    my $out = connect_filer($hostname)->invoke_elem($in);

    my $instances_list = $out->child_get("instances");
    if($instances_list){

        my @instances = $instances_list->children_get();

        foreach my $aggr (@instances){

            my $aggr_name = $aggr->child_get_string("name");

            my $counters_list = $aggr->child_get("counters");
            if($counters_list){

                my @counters =  $counters_list->children_get();

                my %values = (wv_fsinfo_blks_total => undef, wv_fsinfo_blks_used => undef, wv_fsinfo_blks_reserve => undef, wv_fsinfo_blks_snap_reserve_pct => undef, user_reads => undef, user_writes => undef );

                foreach my $counter (@counters){

                    my $key = $counter->child_get_string("name");
                    if(exists $values{$key}){
                        $values{$key} = $counter->child_get_string("value");
                    }
                }

                my $used_space = $values{wv_fsinfo_blks_used} * 4096;
                my $usable_space = ($values{wv_fsinfo_blks_total} - $values{wv_fsinfo_blks_reserve} - $values{wv_fsinfo_blks_snap_reserve_pct} * $values{wv_fsinfo_blks_total} / 100)*4096;
                my $free_space = $usable_space - $used_space;

                $df_return{$aggr_name} = [ $used_space, $free_space, $values{user_reads}, $values{user_writes} ];
            }
        }

        return \%df_return;

    } else {
        return undef;
    }
}

sub cdot_aggr_df {

    my $hostname = shift;
    my %df_return;

    my $api = new NaElement('perf-object-instance-list-info-iter');
    my $xi = new NaElement('desired-attributes');
    $api->child_add($xi);
    my $xi1 = new NaElement('instance-info');
    $xi->child_add($xi1);
    $xi1->child_add_string('uuid','<uuid>');
    $api->child_add_string('objectname','aggregate');
    my $aggr_output = connect_filer($hostname)->invoke_elem($api);

    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","aggregate");
    my $instances = new NaElement('instance-uuids');
    $in->child_add($instances);

    my $aggregates = $aggr_output->child_get("attributes-list");
    my @aggr_result = $aggregates->children_get();

    foreach my $aggr (@aggr_result){
        my $instance = $aggr->child_get("uuid");
        my $uuid = $instance->child_get_string("uuid");
        $instances->child_add_string('instance-uuid',$uuid);
    }

    my $counters = NaElement->new("counters");
    $counters->child_add_string("counter","wv_fsinfo_blks_total");
    $counters->child_add_string("counter","wv_fsinfo_blks_used");
    $counters->child_add_string("counter","wv_fsinfo_blks_reserve");
    $counters->child_add_string("counter","wv_fsinfo_blks_snap_reserve_pct");
    $counters->child_add_string("counter","user_reads");
    $counters->child_add_string("counter","user_writes");
    $in->child_add($counters);
    my $out = connect_filer($hostname)->invoke_elem($in);

    my $instances_list = $out->child_get("instances");
    if($instances_list){

        my @instances = $instances_list->children_get();

        foreach my $aggr (@instances){

            my $aggr_name = $aggr->child_get_string("name");

            my $counters_list = $aggr->child_get("counters");
            if($counters_list){

                my @counters =  $counters_list->children_get();

                my %values = (wv_fsinfo_blks_total => undef, wv_fsinfo_blks_used => undef, wv_fsinfo_blks_reserve => undef, wv_fsinfo_blks_snap_reserve_pct => undef, user_reads => undef, user_writes => undef );

                foreach my $counter (@counters){

                    my $key = $counter->child_get_string("name");
                    if(exists $values{$key}){
                        $values{$key} = $counter->child_get_string("value");
                    }
                }

                my $used_space = $values{wv_fsinfo_blks_used} * 4096;
                my $usable_space = ($values{wv_fsinfo_blks_total} - $values{wv_fsinfo_blks_reserve} - $values{wv_fsinfo_blks_snap_reserve_pct} * $values{wv_fsinfo_blks_total} / 100)*4096;
                my $free_space = $usable_space - $used_space;

                $df_return{$aggr_name} = [ $used_space, $free_space, $values{user_reads}, $values{user_writes} ];      
            }
        }
        return \%df_return;
    } else {
        return undef;
    }
}

sub aggr_module {

    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $aggr_df_result = cdot_aggr_df($hostname);

            if($aggr_df_result){

                foreach my $aggr (keys %$aggr_df_result){

                    my $aggr_value_ref = $aggr_df_result->{$aggr};
                    my @aggr_value = @{ $aggr_value_ref };

                    plugin_dispatch_values({
                            plugin => 'df_aggr',
                            plugin_instance => $aggr,
                            type => 'df_complex',
                            type_instance => 'used',
                            values => [$aggr_value[0]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_aggr',
                            plugin_instance => $aggr,
                            type => 'df_complex',
                            type_instance => 'free',
                            values => [$aggr_value[1]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'iops_aggr',
                            type => 'disk_ops',
                            type_instance => $aggr,
                            values => [$aggr_value[2], $aggr_value[3]],
                            interval => '30',
                            host => $hostname,
                            });
                }
            }
        }

        default {

            my $aggr_df_result = smode_aggr_df($hostname);

            if($aggr_df_result){

                foreach my $aggr (keys %$aggr_df_result){

                    my $aggr_value_ref = $aggr_df_result->{$aggr};
                    my @aggr_value = @{ $aggr_value_ref };

                    plugin_dispatch_values({
                            plugin => 'df_aggr',
                            plugin_instance => $aggr,
                            type => 'df_complex',
                            type_instance => 'used',
                            values => [$aggr_value[0]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_aggr',
                            plugin_instance => $aggr,
                            type => 'df_complex',
                            type_instance => 'free',
                            values => [$aggr_value[1]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'iops_aggr',
                            type => 'disk_ops',
                            type_instance => $aggr,
                            values => [$aggr_value[2], $aggr_value[3]],
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

