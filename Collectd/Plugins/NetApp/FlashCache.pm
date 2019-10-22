# --
# NetApp/FlashCache.pm - Collectd Perl Plugin for NetApp Storage Systems (FlashCache Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2018 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::FlashCache;

use base 'Exporter';
our @EXPORT = qw(flashcache_module);

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

sub flashcache_module {

    my $hostname = shift;
    my $starttime = time();

    my @nics;

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "ext_cache_obj");
    };
    plugin_log(LOG_INFO, "*DEBUG* connect fail cdot_flashcache: $@") if $@;

    my $nics = $output->child_get("attributes-list");

    if($nics){

        my @result = $nics->children_get();

        foreach my $interface (@result){
            my $if_name = $interface->child_get_string("name");
            my $uuid = $interface->child_get_string("uuid");
            push(@nics, $uuid);
        }

        my $api = new NaElement('perf-object-get-instances');
        my $xi = new NaElement('counters');
        $api->child_add($xi);
        $xi->child_add_string('counter','hit_percent');
        $xi->child_add_string('counter','accesses');
        my $xi1 = new NaElement('instance-uuids');
        $api->child_add($xi1);

        foreach my $nic_uuid (@nics){
            $xi1->child_add_string('instance-uuid',$nic_uuid);
        }

        $api->child_add_string('objectname','ext_cache_obj');

        my $xo;
        eval {
            $xo = connect_filer($hostname)->invoke_elem($api);
        };
        plugin_log(LOG_INFO, "*DEBUG* connect fail flashcache: $@") if $@;

        my $instances = $xo->child_get("instances");
        if($instances){

            my @instance_data = $instances->children_get("instance-data");

            foreach my $nic (@instance_data){

                my $nic_name = $nic->child_get_string("uuid");
                $nic_name =~ s/:kernel:ec0//;

                my $counters = $nic->child_get("counters");
                if($counters){

                    my @counter_result = $counters->children_get();

                    my %values = (hit_percent => undef, accesses => undef);

                    foreach my $counter (@counter_result){

                        my $key = $counter->child_get_string("name");
                        if(exists $values{$key}){
                            $values{$key} = $counter->child_get_string("value");
                        }
                    }

                    my $percent = $values{hit_percent}/$values{accesses}*100;

                    #plugin_log(LOG_INFO, "*DEBUG* flashcache: $nic_name: $percent");

                    plugin_dispatch_values({
                            plugin => 'flashcache',
                            type => 'percent',
                            type_instance => $nic_name,
                            values => [$percent],
                            interval => '30',
                            host => $hostname,
                            time => $starttime,
                            });

                }
            }
        }
    } else {
        plugin_log(LOG_INFO, "*DEBUG* no flashcache found on $hostname");
        return undef;
    }

    return 1;

}

1;

