# --
# NetApp/Flash.pm - Collectd Perl Plugin for NetApp Storage Systems (Flash Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::Flash;

use base 'Exporter';
our @EXPORT = qw(flash_module);

use strict;
use warnings;

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub cdot_flash {

    my $hostname = shift;

    my $aggr_output;
    eval {
        $aggr_output = connect_filer($hostname)->invoke("aggr-get-iter");
    };
    plugin_log("DEBUG_LOG", "connect fail cdot_flash: $@") if $@;

    my $aggrs = $aggr_output->child_get("attributes-list");
    my @aggr_result = $aggrs->children_get();

    my %aggr_transfers;
    my %aggr_name_mapping;
    my @hybrid_aggrs;

    foreach my $aggr (@aggr_result){
        my $aggr_name = $aggr->child_get_string("aggregate-name");
        my $aggr_raid = $aggr->child_get("aggr-raid-attributes");
        my $hybrid = $aggr_raid->child_get_string("is-hybrid");

        if($hybrid eq "true"){
            push(@hybrid_aggrs, $aggr_name);
        }
    }

    my $name_output;
    eval { 
        $name_output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "aggregate");
    };
    plugin_log("DEBUG_LOG", "connect fail name_output: $@") if $@;

    my $name_list = $name_output->child_get("attributes-list");
    my @name_result = $name_list->children_get();

    foreach my $name_id (@name_result){
        my $aggr_name = $name_id->child_get_string("name");
        my $aggr_uuid = $name_id->child_get_string("uuid");
        $aggr_name_mapping{$aggr_name} = $aggr_uuid;
    }

    my $perf_api = new NaElement('perf-object-get-instances');
    my $perf_counters = new NaElement('counters');
    $perf_api->child_add($perf_counters);
    $perf_counters->child_add_string('counter','user_read_blocks');
    $perf_counters->child_add_string('counter','user_read_blocks_ssd');
    $perf_counters->child_add_string('counter','user_write_blocks');
    $perf_counters->child_add_string('counter','user_write_blocks_ssd');

    my $perf_uuids = new NaElement('instance-uuids');
    $perf_api->child_add($perf_uuids);

    foreach (@hybrid_aggrs){
        my $aggregate_id = $aggr_name_mapping{$_};
        $perf_uuids->child_add_string('instance-uuid',$aggregate_id);
    }

    $perf_api->child_add_string('objectname','aggregate');

    my $perf_output;
    eval {
        $perf_output = connect_filer($hostname)->invoke_elem($perf_api);
    };
    plugin_log("DEBUG_LOG", "connect fail perf_output: $@") if $@;

    my $instances = $perf_output->child_get("instances");
    if($instances){

        my @instance_result = $instances->children_get();

        foreach my $instance (@instance_result){

            my $counters = $instance->child_get("counters");
            if($counters){
                my @result = $counters->children_get();

                my %values = (user_read_blocks => undef, user_read_blocks_ssd => undef, user_write_blocks => undef, user_write_blocks_ssd => undef);

                foreach my $counter (@result){
                    my $key = $counter->child_get_string("name");
                    if(exists $values{$key}){
                        $values{$key} = $counter->child_get_string("value");
                    }
                }

                my $name = $instance->child_get_string("name");
                $aggr_transfers{$name} = [ $values{user_read_blocks}, $values{user_read_blocks_ssd}, $values{user_write_blocks}, $values{user_write_blocks_ssd} ];
            }
        }
    }
    return \%aggr_transfers;
}

sub flash_module {
   
    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $flash_result;
            eval {
                $flash_result = cdot_flash($hostname);
            };
            plugin_log("DEBUG_LOG", "cdot_flash: $@") if $@;

            if($flash_result){

                foreach my $aggr (keys %$flash_result){

                    my $aggr_value_ref = $flash_result->{$aggr};
                    my @aggr_value = @{ $aggr_value_ref };                 
    
                    plugin_dispatch_values({
                            plugin => 'flash_usage',
                            type => 'netapp_flash_usage',
                            type_instance => $aggr,
                            values => [@aggr_value],
                            interval => '30',
                            host => $hostname,
                            });
                }
            }
        }

        default {

        # do nothing

        }
    }

    return 1;
}

1;

