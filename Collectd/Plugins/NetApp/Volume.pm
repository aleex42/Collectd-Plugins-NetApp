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
no warnings "experimental";

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub cdot_vol_perf {

    my $hostname = shift;
    my %perf_return = ();

    my $vol_api = new NaElement('volume-get-iter');
    my $tag_elem = NaElement->new( "tag" );
    $vol_api->child_add( $tag_elem );
    my $vol_xi = new NaElement('desired-attributes');
    $vol_api->child_add($vol_xi);
    my $vol_xi1 = new NaElement('volume-attributes');
    $vol_xi->child_add($vol_xi1);
    my $vol_xi4 = new NaElement('volume-id-attributes');
    $vol_xi4->child_add_string('instance-uuid','instance-uuid');
    $vol_xi1->child_add($vol_xi4);

    my $next = "";

    while(defined($next)) {
        unless ($next eq "") {
            $tag_elem->set_content( $next );
        }

        $vol_api->child_add_string( "max-records", 500 );

        my $vol_output;
        eval {  
            $vol_output = connect_filer($hostname)->invoke_elem($vol_api);
        };
#plugin_log(LOG_INFO, "*DEBUG* connect fail cdot_vol_perf: $@") if $@;

        my $vol_instances_list = $vol_output->child_get("attributes-list");

        if($vol_instances_list){

            my @vol_instances = $vol_instances_list->children_get();

            my %vol_uuids;

            foreach my $vol (@vol_instances){
                my $vol_id_attributes = $vol->child_get("volume-id-attributes");
                my $vol_uuid = $vol_id_attributes->child_get_string("instance-uuid");
                my $vol_name = $vol_id_attributes->child_get_string("name");

# ONTAP 9.2 no uuid?
                if($vol_uuid){

                    unless($vol_name =~ m/temp__/){   
                        $vol_uuids{$vol_uuid} = $vol_name;
                    }
                }
            }

            my $api = new NaElement('perf-object-get-instances');
            my $xi = new NaElement('counters');
            $api->child_add($xi);
            $xi->child_add_string('counter','write_ops');
            $xi->child_add_string('counter','read_ops');
            $xi->child_add_string('counter','read_data');
            $xi->child_add_string('counter','write_data');
            $xi->child_add_string('counter','avg_latency');
            $xi->child_add_string('counter','total_ops');
            $xi->child_add_string('counter','read_latency');
            $xi->child_add_string('counter','write_latency');
            my $xi1 = new NaElement('instance-uuids');
            $api->child_add($xi1);

            foreach my $vol_uuid (keys %vol_uuids){
                $xi1->child_add_string("instance-uuid", $vol_uuid);
            }

            $api->child_add_string('objectname','volume');

            my $xo;
            eval {
                $xo = connect_filer($hostname)->invoke_elem($api);
            };
            plugin_log(LOG_INFO, "*DEBUG* connect fail cdot_vol_perf: $@") if $@;

            my $instances_list = $xo->child_get("instances");
            if($instances_list){

                my @instances = $instances_list->children_get();

                foreach my $volume (@instances){

                    my $vol_uuid = $volume->child_get_string("uuid");
                    my $vol_name = $vol_uuids{$vol_uuid};

                    if($vol_name =~ m/vol0/){
                        next;
                    }

#plugin_log(LOG_INFO, "--> $vol_name");

                    my $counters_list = $volume->child_get("counters");
                    if($counters_list){
                        my @counters =  $counters_list->children_get();

                        my %values = (read_ops => undef, write_ops => undef, write_data => undef, read_data => undef, read_latency => undef, write_latency => undef);

                        foreach my $counter (@counters) {

                            my $key = $counter->child_get_string("name");

                            if (exists $values{$key}) {
                                $values{$key} = $counter->child_get_string("value");
                            }
                        }

                        unless(defined($perf_return{$vol_name})){

                            $perf_return{$vol_name} = [$values{read_latency}, $values{write_latency}, $values{read_ops}, $values{write_ops}];

                            unless(($values{read_latency} eq "0") && ($values{write_latency} eq "0") && ($values{read_ops} eq "0") && ($values{write_ops} eq "0")){

                                plugin_dispatch_values({
                                        plugin => 'latency_vol',
                                        type => 'netapp_vol_latency',
                                        type_instance => $vol_name,
                                        values => [ $values{read_latency}, $values{write_latency}, $values{read_ops}, $values{write_ops} ],
                                        interval => '30',
                                        host => $hostname,
                                        });
                            }

                            unless(($values{read_data} eq "0") && ($values{write_data} eq "0")){

                                plugin_dispatch_values({
                                        plugin => 'traffic_vol',
                                        type => 'disk_octets',
                                        type_instance => $vol_name,
                                        values => [ $values{read_data}, $values{write_data} ],
                                        interval => '30',
                                        host => $hostname,
                                        });
                            }

                            unless(($values{read_ops} eq "0") && ($values{write_ops} eq "0")){

                                plugin_dispatch_values({
                                        plugin => 'iops_vol',
                                        type => 'disk_ops',
                                        type_instance => $vol_name,
                                        values => [ $values{read_ops}, $values{write_ops} ],
                                        interval => '30',
                                        host => $hostname,
                                        }); 
                            }
                        }
                    }
                }
            }
        }

        $next = $vol_output->child_get_string( "next-tag" );

    }
    return \%perf_return;
}

sub volume_module {

    my $hostname = shift;
    my $starttime = time();

    my $perf_result;
    eval {
        $perf_result = cdot_vol_perf($hostname);
    };
    plugin_log(LOG_INFO, "*DEBUG* cdot_vol_perf: $@") if $@;

    return 1;
}

1;

