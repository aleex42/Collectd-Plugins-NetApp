# --
# NetApp/Volume.pm - Collectd Perl Plugin for NetApp Storage Systems (Volume Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::Volume;

use base 'Exporter';
our @EXPORT = qw(volume_module);

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

sub cdot_vol_df {

    my $hostname = shift;
    my %df_return;

    my $api = new NaElement('volume-get-iter');
    my $xi = new NaElement('desired-attributes');
    $api->child_add($xi);
    my $xi1 = new NaElement('volume-attributes');
    $xi->child_add($xi1);
    my $xi2 = new NaElement('volume-space-attributes');
    $xi1->child_add($xi2);
    $xi2->child_add_string('size-available','<size-available>');
    $xi2->child_add_string('size-used','<size-used>');
    my $xi3 = new NaElement('volume-state-attributes');
    $xi1->child_add($xi3);
    $xi3->child_add_string('state','<state>');
    my $xi4 = new NaElement('volume-id-attributes');
    $xi4->child_add_string('name','name');
    $api->child_add_string('max-records','1000');

    my $output = connect_filer($hostname)->invoke_elem($api);

    my $volumes = $output->child_get("attributes-list");
    my @result = $volumes->children_get();

    if($output){

        foreach my $vol (@result){

            my $vol_state_attributes = $vol->child_get("volume-state-attributes");

            if($vol->child_get("volume-state-attributes")){

                my $vol_info = $vol->child_get("volume-id-attributes");
                my $vol_name = $vol_info->child_get_string("name");

                if($vol_state_attributes->child_get_string("state") eq "online"){

                    my $vol_space = $vol->child_get("volume-space-attributes");

                    my $used = $vol_space->child_get_string("size-used");
                    my $free = $vol_space->child_get_int("size-available");

                    $df_return{$vol_name} = [ $used, $free ];
                }
            }
        }

        return \%df_return;

    } else {

        return undef;

    }
}

sub smode_vol_df {

    my $hostname = shift;
    my %df_return;

    my $out = connect_filer($hostname)->invoke("volume-list-info");

    my $instances_list = $out->child_get("volumes");
    my @instances = $instances_list->children_get();

    foreach my $volume (@instances){

        my $vol_name = $volume->child_get_string("name");

        my $snap = NaElement->new("snapshot-list-info");
        $snap->child_add_string("volume",$vol_name);
        my $snap_out = connect_filer($hostname)->invoke_elem($snap);

        my $snap_instances_list = $snap_out->child_get("snapshots");

        if($snap_instances_list){

            my @snap_instances = $snap_instances_list->children_get();

            my $cumulative = 0;

            foreach my $snap (@snap_instances){
                if($snap->child_get_int("cumulative-total") > $cumulative){
                    $cumulative = $snap->child_get_int("cumulative-total");
                }
            }

            my $snap_used = $cumulative*1024;
            my $vol_free = $volume->child_get_int("size-available");
            my $vol_used = $volume->child_get_int("size-used");

            my $snap_reserved = $volume->child_get_int("snapshot-blocks-reserved") * 1024;
            my $snap_norm_used;
            my $snap_reserve_free;
            my $snap_reserve_used;        

            if($snap_reserved > $snap_used){
                $snap_reserve_free = $snap_reserved - $snap_used;
                $snap_reserve_used = $snap_used;
                $snap_norm_used = 0;
            } else {
                $snap_reserve_free = 0;
                $snap_reserve_used = $snap_reserved;
                $snap_norm_used = $snap_used - $snap_reserved;
            }

            if ( $vol_used >= $snap_norm_used){
                $vol_used = $vol_used - $snap_norm_used;
            } 

            $df_return{$vol_name} = [ $vol_free, $vol_used, $snap_reserve_free, $snap_reserve_used, $snap_norm_used];

        }           
    }

    return \%df_return;
}

sub volume_module {

    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $df_result = cdot_vol_df($hostname);

            if($df_result){

                foreach my $vol (keys %$df_result){

                    my $vol_value_ref = $df_result->{$vol};
                    my @vol_value = @{ $vol_value_ref };

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'used',
                            values => [$vol_value[0]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'free',
                            values => [$vol_value[1]],
                            interval => '30',
                            host => $hostname,
                            });
                }                   
            }
        }

        default {

            my $df_result = smode_vol_df($hostname);

            if($df_result){

                foreach my $vol (keys %$df_result){

                    my $vol_value_ref = $df_result->{$vol};
                    my @vol_value = @{ $vol_value_ref };

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'free',
                            values => [$vol_value[0]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'used',
                            values => [$vol_value[1]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'snap_reserve_free',
                            values => [$vol_value[2]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'snap_reserve_used',
                            values => [$vol_value[3]],
                            interval => '30',
                            host => $hostname,
                            });

                    plugin_dispatch_values({
                            plugin => 'df_vol',
                            plugin_instance => $vol,
                            type => 'df_complex',
                            type_instance => 'snap_norm_used',
                            values => [$vol_value[4]],
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

