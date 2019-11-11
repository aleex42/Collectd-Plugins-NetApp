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
no warnings "experimental";

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Data::Dumper;

use Config::Simple;

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

    my $aggr_output;
    eval {
        $aggr_output = connect_filer($hostname)->invoke_elem($api);
    };
    plugin_log(LOG_INFO, "*DEBUG* connect filer: $@") if $@;


    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","aggregate");
    my $instances = new NaElement('instance-uuids');
    $in->child_add($instances);

    my $aggregates = $aggr_output->child_get("attributes-list");
    if($aggregates){

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
    
        my $out;
        eval {
            $out = connect_filer($hostname)->invoke_elem($in);
        };
        plugin_log(LOG_INFO, "*DEBUG* cdot_aggr_df") if $@;
    
        my $instances_list = $out->child_get("instances");
        if($instances_list){
    
            my @instances = $instances_list->children_get();
   
            my $ultra_free = 0;
            my $performance_free = 0;
            my $mass_free = 0;
            my $ultra_used = 0;
            my $performance_used = 0;
            my $mass_used = 0;
 
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
                
                    if(($aggr_name =~ m/ata/) || ($aggr_name =~ m/mass/)){
                        $mass_used += $used_space;
                        $mass_free += $free_space;
                    } elsif(($aggr_name =~ m/ssd/) || ($aggr_name =~ m/ultra/)){
                        $ultra_used += $used_space;
                        $ultra_free += $free_space;
                    } elsif(($aggr_name =~ m/sas/) || ($aggr_name =~ m/performance/)){
                        $performance_used += $used_space;
                        $performance_free += $free_space;
                    }
                }
            }





            $df_return{ultra} = [ $ultra_used, $ultra_free, undef, undef ];
            $df_return{performance} = [ $performance_used, $performance_free, undef, undef ];
            $df_return{mass} = [ $mass_used, $mass_free, undef, undef ];

            return \%df_return;

        } else {
            plugin_log(LOG_INFO, "*DEBUG* cdot_aggr_df no aggr instance found: $hostname");
            return undef;
        }
    } else {
        plugin_log(LOG_INFO, "*DEBUG* cdot_aggr_df no aggregates found: $hostname");
        return undef;
    }
}

sub cdot_aggr_df_reserved {

    my %aggr_df = ();

    my $hostname = shift;

    my $api = new NaElement('volume-get-iter');
    my $xi = new NaElement('desired-attributes');
    $api->child_add($xi);
    my $xi1 = new NaElement('volume-attributes');
    $xi->child_add($xi1);
    my $xi2 = new NaElement('volume-space-attributes');
    $xi1->child_add($xi2);
    $xi2->child_add_string('size-total','<size-total>');
    my $xi3 = new NaElement('volume-state-attributes');
    $xi1->child_add($xi3);
    $xi3->child_add_string('state','<state>');
    my $xi4 = new NaElement('volume-id-attributes');
    $xi1->child_add($xi4);
    $xi4->child_add_string('name','name');
    $xi4->child_add_string('containing-aggregate-name','<containing-aggregate-name>');
    $api->child_add_string('max-records','10000');

   my $output;
   eval {
       $output = connect_filer($hostname)->invoke_elem($api);
   };
   plugin_log(LOG_INFO, "*DEBUG* connect filer: $@") if $@;

    my $volumes = $output->child_get("attributes-list");

    if($volumes){

    my @result = $volumes->children_get();

        my $ultra_total = 0;
        my $performance_total = 0;
        my $mass_total = 0;

        foreach my $vol (@result){

            my $vol_state_attributes = $vol->child_get("volume-state-attributes");

            if($vol->child_get("volume-state-attributes")){

                my $vol_info = $vol->child_get("volume-id-attributes");
                my $vol_name = $vol_info->child_get_string("name");
                my $aggr = $vol_info->child_get_string("containing-aggregate-name");

                if($vol_state_attributes->child_get_string("state") eq "online"){

                    my $vol_space = $vol->child_get("volume-space-attributes");

                    my $total = $vol_space->child_get_string("size-total");

                    # Flexgroup has no aggr
                    if($aggr){

                        if($aggr_df{$aggr}){
                            $aggr_df{$aggr} += $total;
                        } else {
                            $aggr_df{$aggr} = $total;
                        }

                        unless($aggr =~ m/aggr0_/){

                            if(($aggr =~ m/ata/) || ($aggr =~ m/mass/)){
                                $mass_total += $total;
                            } elsif(($aggr =~ m/ssd/) || ($aggr =~ m/ultra/)){
                                $ultra_total += $total;
                            } elsif(($aggr =~ m/sas/) || ($aggr =~ m/performance/)){
                                $performance_total += $total;
                            }
                        }
                    }
                }
            }
        }

        $aggr_df{ultra} = $ultra_total;
        $aggr_df{performance} = $performance_total;
        $aggr_df{mass} = $mass_total;

        return \%aggr_df;

    } else {

        return undef;

    }
}

sub aggr_module {

    my $hostname = shift;
    my $starttime = time();

    my $aggr_df_result;

    eval {
        $aggr_df_result = cdot_aggr_df($hostname);
    };            
#    plugin_log(LOG_INFO, "*DEBUG* cdot_aggr_df: $@") if $@;

    if($aggr_df_result){

        foreach my $aggr (keys %$aggr_df_result){

            my $aggr_value_ref = $aggr_df_result->{$aggr};
            my @aggr_value = @{ $aggr_value_ref };

            unless($aggr_value[0] eq "0"){

            plugin_log(LOG_INFO, "*DEBUG* $aggr_value[0]");

            plugin_dispatch_values({
                    plugin => 'df_aggr',
                    plugin_instance => $aggr,
                    type => 'df_complex',
                    type_instance => 'used',
                    values => [$aggr_value[0]],
                    interval => '30',
                    host => $hostname,
                    time => $starttime,
                    });

            } else {

            plugin_dispatch_values({
                    plugin => 'df_aggr',
                    plugin_instance => $aggr,
                    type => 'df_complex',
                    type_instance => 'used',
                    values => ['U'],
                    interval => '30',
                    host => $hostname,
                    time => $starttime,
                    });

            }


            plugin_dispatch_values({
                    plugin => 'df_aggr',
                    plugin_instance => $aggr,
                    type => 'df_complex',
                    type_instance => 'free',
                    values => [$aggr_value[1]],
                    interval => '30',
                    host => $hostname,
                    time => $starttime,
                    });

            unless(($aggr eq "mass") || ($aggr eq "performance") || ($aggr eq "ultra")){

                plugin_dispatch_values({
                        plugin => 'iops_aggr',
                        type => 'disk_ops',
                        type_instance => $aggr,
                        values => [$aggr_value[2], $aggr_value[3]],
                        interval => '30',
                        host => $hostname,
                        time => $starttime,
                        });
            }
        }
    }

    my $aggr_df_reserved;

    eval {
        $aggr_df_reserved = cdot_aggr_df_reserved($hostname);
    };
    plugin_log(LOG_INFO, "*DEBUG* cdot_aggr_df_reserved: $@") if $@;

    if($aggr_df_reserved){

        foreach my $aggr (keys %$aggr_df_reserved){

            my $aggr_value = $aggr_df_reserved->{$aggr};


#            plugin_log(LOG_INFO, "*DEBUG* aggr_reserv: $aggr_value");

            unless($aggr_value eq "0"){

            plugin_dispatch_values({
                    plugin => 'df_aggr_reserved',
                    plugin_instance => $aggr,
                    type => 'df_complex',
                    type_instance => 'used',
                    values => [$aggr_value],
                    interval => '30',
                    host => $hostname,
                    time => $starttime,
                    });

            }
        }
    }

    return 1;
}

1;

