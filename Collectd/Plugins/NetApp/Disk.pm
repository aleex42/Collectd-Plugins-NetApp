# --
# NetApp/Disk.pm - Collectd Perl Plugin for NetApp Storage Systems (Disk Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::Disk;

use base 'Exporter';
our @EXPORT = qw(disk_module);

use strict;
use warnings;
no warnings "experimental";

use feature qw(switch);

use Data::Dumper;

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub smode_disk {

    my $hostname = shift;

    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","disk");
    my $counters = NaElement->new("counters");
    $counters->child_add_string("counter","raid_name");
    $counters->child_add_string("counter","disk_busy");
    $counters->child_add_string("counter","base_for_disk_busy");
    $in->child_add($counters);

    my $out;
    eval {
        $out = connect_filer($hostname)->invoke_elem($in);
    };
    plugin_log(LOG_DEBUG, "*DEBUG* connect fail smode_disk: $@") if $@;

    my ($raid_name, $disk_busy, $base_disk_busy);

    my $instances_list = $out->child_get("instances");

    if($instances_list){

        my @instances = $instances_list->children_get();

        my %max_percent;

        foreach my $disk (@instances){

            my $counters_list = $disk->child_get("counters");
            if($counters){

                my @counters =  $counters_list->children_get();
                my %values = (raid_name => undef, disk_busy => undef, base_for_disk_busy => undef);
    
                foreach my $counter (@counters){
                    my $key = $counter->child_get_string("name");
                    if(exists $values{$key}){
                        $values{$key} = $counter->child_get_string("value");
                    }
                }
    
                my (undef, $aggr_key, undef, undef, $disc) = split m!/!, $values{raid_name};
                next unless $aggr_key && $disc;
    
                if ($max_percent{$aggr_key}){
                    if ($values{disk_busy} > $max_percent{$aggr_key}){
                        $max_percent{$aggr_key} = [$values{disk_busy}, $values{base_for_disk_busy}];
                    }
                } else {
                    $max_percent{$aggr_key} = [$values{disk_busy}, $values{base_for_disk_busy}];
                }
            }
        }
        return \%max_percent;
    } else {
        return undef;
    }
}


sub cdot_disk {

    my $hostname = shift;

    my $iterator = NaElement->new( "storage-disk-get-iter" );
    my $xi = new NaElement('desired-attributes');
    $iterator->child_add($xi);
    my $xi1 = new NaElement('storage-disk-info');
    $xi->child_add($xi1);
    my $xi7 = new NaElement('disk-raid-info');
    $xi1->child_add($xi7);
    my $xi9 = new NaElement('disk-uid');
    my $xi8 = new NaElement('disk-aggregate-info');
    $xi7->child_add($xi8);
    $xi7->child_add($xi9);
    $xi8->child_add_string('aggregate-name','<aggregate-name>');
    my $xi10 = new NaElement('disk-shared-info');
    $xi7->child_add($xi10);

    my $tag_elem = NaElement->new( "tag" );
    $iterator->child_add( $tag_elem );

    my $next = "";
    my %max_percent = ();
    my %disk_list = ();    

    my @disk_name_list;

    while(defined( $next )){
        unless ($next eq "") {
            $tag_elem->set_content( $next );
        }

        $iterator->child_add_string( "max-records", 500 );
        my $output = connect_filer($hostname)->invoke_elem( $iterator );

        if ($output->results_errno != 0) {
            my $r = $output->results_reason();
            print "UNKNOWN: $r\n";
            exit 3;
        }

        unless($output->child_get_int( "num-records" ) eq "0") {

            my $disks = $output->child_get( "attributes-list" );
            my @result = $disks->children_get();

            foreach my $disk (@result) {

                my $raid_info = $disk->child_get("disk-raid-info");
                my $disk_uuid = $raid_info->child_get_int("disk-uid");

                my $shared_info = $raid_info->child_get("disk-shared-info");

                if($shared_info){

                    my $shared_aggrs = $shared_info->child_get("aggregate-list");
                    if($shared_aggrs){

                        my @aggrs = $shared_aggrs->children_get();

                        foreach(@aggrs){
                            my $aggr_name = $_->child_get_string("aggregate-name");
                            if($aggr_name){
                                push (@{$disk_list{$aggr_name}}, $disk_uuid);
                                push (@disk_name_list, $disk_uuid);
                            }
                        }
                    }
                }

                if($raid_info->child_get("disk-aggregate-info")){

                    my $aggr_info = $raid_info->child_get("disk-aggregate-info");
                    my $aggr_name = $aggr_info->child_get_int("aggregate-name");

                    if($aggr_name){
                        push (@{$disk_list{$aggr_name}}, $disk_uuid);
                        push (@disk_name_list, $disk_uuid);
                    }
                }
            }
        }

        $next = $output->child_get_string( "next-tag" );

    }

    my $count = 1;
    my $split = 500;

    my @split_disks;

    foreach my $disk (@disk_name_list){

        my $split_count = $count/$split;
        $split_count = sprintf("%d", $split_count);
            
        push(@{ $split_disks[$split_count] }, $disk);

        $count++;
    }

    my %disk_perf_values;

    foreach (@split_disks){

        my $perf_api = new NaElement('perf-object-get-instances');
        my $perf_counters = new NaElement('counters');
        $perf_api->child_add($perf_counters);
        $perf_counters->child_add_string('counter','base_for_disk_busy');
        $perf_counters->child_add_string('counter','disk_busy');
    
        my $perf_uuids= new NaElement('instance-uuids');
        $perf_api->child_add($perf_uuids);
    
        foreach my $disk_id (@{ $_ }){
        $perf_uuids->child_add_string('instance-uuid',$disk_id);
        }
        $perf_api->child_add_string('objectname','disk');
    
        my $perf_output;
        
        eval {
            $perf_output = connect_filer($hostname)->invoke_elem($perf_api);
        };
        plugin_log("DEBUG_LOG", "*DEBUG* connect fail perf_output: $@") if $@;
        
        my $instances = $perf_output->child_get("instances");
        if($instances){
        
            my @instance_result = $instances->children_get();
        
            foreach my $instance (@instance_result){
        
                my $counters = $instance->child_get("counters");
                if($counters){
        
                    my @result = $counters->children_get();
        
                    my %values = (disk_busy => undef, base_for_disk_busy => undef);
        
                    foreach my $counter (@result){
                        my $key = $counter->child_get_string("name");
                        if(exists $values{$key}){
                            $values{$key} = $counter->child_get_string("value");
                        }
                    }
                    my $uuid = $instance->child_get_string("uuid");
        
                    $disk_perf_values{$uuid} = "$values{disk_busy}, $values{base_for_disk_busy}";
    
                }
            }
        }
    }

    my %disk_perf = ();

    foreach my $aggr (keys %disk_list){

        foreach my $disk_id (@{$disk_list{$aggr}}){

            my @disk_perf_values = split(/,/, $disk_perf_values{$disk_id});
            my $disk_busy = $disk_perf_values[0];
            my $base_for_disk_busy = $disk_perf_values[1];

            if ($max_percent{$aggr}){
                my $ref = $max_percent{$aggr};
                my @busy_value = @{ $ref };

                if ($disk_busy > $busy_value[0]){
                    $max_percent{$aggr} = [ $disk_busy, $base_for_disk_busy ];
                }
            } else {
                $max_percent{$aggr} = [ $disk_busy, $base_for_disk_busy ];
            }
        }
    
        my $aggr_value_ref = $max_percent{$aggr};
        my @aggr_value = @{ $aggr_value_ref };

        plugin_dispatch_values({
                plugin => 'disk_busy',
                type => 'netapp_disk_busy',
                type_instance => $aggr,
                values => [ @aggr_value ],
                interval => '30',
                host => $hostname,
        });

    }

    return \%max_percent;

}

sub disk_module {
   
    my ($hostname, $filer_os) = @_;
    my $starttime = time();

    given ($filer_os){

        when("cDOT"){

            my $disk_result;
            eval {
                $disk_result = cdot_disk($hostname);
            };
            plugin_log(LOG_DEBUG, "*DEBUG* cdot_disk: $@") if $@;

        }

        default {

            my $disk_result;
            eval {
                $disk_result = smode_disk($hostname);
            };
            plugin_log(LOG_DEBUG, "*DEBUG* smode_disk: $@") if $@;

            if($disk_result){

                foreach my $aggr (keys %$disk_result){

                    my $aggr_value_ref = $disk_result->{$aggr};
                    my @aggr_value = @{ $aggr_value_ref };

                    plugin_dispatch_values({
                            plugin => 'disk_busy',
                            type => 'netapp_disk_busy',
                            type_instance => $aggr,
                            values => [@aggr_value],
                            interval => '30',
                            host => $hostname,
                            time => $starttime,
                            });
                }
            }
        }
    }

    return 1;
}

1;

