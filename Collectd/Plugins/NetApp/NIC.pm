# --
# NetApp/NIC.pm - Collectd Perl Plugin for NetApp Storage Systems (NIC Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::NIC;

use base 'Exporter';
our @EXPORT = qw(nic_module);

use strict;
use warnings;

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
use NaServer;
use NaElement;

use Config::Simple;

sub cdot_lif {

    my $hostname = shift;
    my %nic_return;
    my @nics;

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "lif");
    };
    plugin_log("DEBUG_LOG", "*DEBUG* connect fail cdot_lif: $@") if $@;

    my $nics = $output->child_get("attributes-list");

    if($nics){

        my @result = $nics->children_get();
   
        foreach my $interface (@result){
    
            my $if_name = $interface->child_get_string("name");

            if(($if_name !~ "e0P\$") && ($if_name !~ "losk\$")){
    
                my $uuid = $interface->child_get_string("uuid");
                push(@nics, $uuid);
            }
        }

        my $api = new NaElement('perf-object-get-instances');
        my $xi = new NaElement('counters');
        $api->child_add($xi);
        $xi->child_add_string('counter','sent_data');
        $xi->child_add_string('counter','recv_data');
        my $xi1 = new NaElement('instance-uuids');
        $api->child_add($xi1);
    
        foreach my $nic_uuid (@nics){
            $xi1->child_add_string('instance-uuid',$nic_uuid);
        }
    
        $api->child_add_string('objectname','lif');
    
        my $xo;
        eval {
            $xo = connect_filer($hostname)->invoke_elem($api);
        };
        plugin_log("DEBUG_LOG", "*DEBUG* connect fail nics: $@") if $@;

        my $instances = $xo->child_get("instances");
        if($instances){

            my @instance_data = $instances->children_get("instance-data");

            foreach my $nic (@instance_data){

                my $nic_name = $nic->child_get_string("name");

                #plugin_log("LOG_DEBUG", "--> $nic_name");

                my $counters = $nic->child_get("counters");
                if($counters){

                    my @counter_result = $counters->children_get();

                    my %values = (sent_data => undef, recv_data => undef);

                    foreach my $counter (@counter_result){

                        my $key = $counter->child_get_string("name");
                        if(exists $values{$key}){
                            $values{$key} = $counter->child_get_string("value");
                        }
                    }
                    $nic_return{$nic_name} = [ $values{recv_data}, $values{sent_data} ];
                }
            }
        }
        return \%nic_return;
    } else {
        return undef;
    }
}

sub cdot_port {

    my $hostname = shift;
    my %port_return;
    my @nics;

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "nic_common");
    };
    plugin_log("DEBUG_LOG", "*DEBUG* connect fail cdot_port: $@") if $@;

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
        $xi->child_add_string('counter','rx_total_bytes');
        $xi->child_add_string('counter','tx_total_bytes');
        my $xi1 = new NaElement('instance-uuids');
        $api->child_add($xi1);

        foreach my $nic_uuid (@nics){
            $xi1->child_add_string('instance-uuid',$nic_uuid);
        }

        $api->child_add_string('objectname','nic_common');

        my $xo;
        eval {
            $xo = connect_filer($hostname)->invoke_elem($api);
        }; 
        plugin_log("DEBUG_LOG", "*DEBUG* connect fail cdot_port: $@") if $@;

        my $instances = $xo->child_get("instances");
        if($instances){

            my @instance_data = $instances->children_get("instance-data");

            foreach my $nic (@instance_data){

                my $nic_name = $nic->child_get_string("uuid");
                $nic_name =~ s/kernel://;

                my $counters = $nic->child_get("counters");
                if($counters){

                    my @counter_result = $counters->children_get();

                    my %values = (tx_total_bytes => undef, rx_total_bytes => undef);

                    foreach my $counter (@counter_result){

                        my $key = $counter->child_get_string("name");
                        if(exists $values{$key}){
                            $values{$key} = $counter->child_get_string("value");
                        }
                    }
                    $port_return{$nic_name} = [ $values{rx_total_bytes}, $values{tx_total_bytes} ];
                }
            }
        }
        return \%port_return;
    } else {
        return undef;
    }
}


sub smode_nic {

    my $hostname = shift;
    my %nic_return;

    my $in = NaElement->new("perf-object-get-instances");
    $in->child_add_string("objectname","ifnet");
    my $counters = NaElement->new("counters");    
    $counters->child_add_string("counter","recv_data");
    $counters->child_add_string("counter","send_data");
    $in->child_add($counters);

    my $out;
    eval {
        $out = connect_filer($hostname)->invoke_elem($in);
    };
    plugin_log("DEBUG_LOG", "*DEBUG* connect fail smode_nic: $@") if $@;

    my $instances_list = $out->child_get("instances");
    
    if($instances_list){

        my @instances = $instances_list->children_get();

        foreach my $interface (@instances){

            my $int_name = $interface->child_get_string("name");

            my $counters_list = $interface->child_get("counters");
            if($counters_list){
                my @counters = $counters_list->children_get();

                my %values = (recv_data => undef, send_data => undef);

                foreach my $counter (@counters){

                    my $key = $counter->child_get_string("name");
                    if(exists $values{$key}){
                        $values{$key} = $counter->child_get_string("value");
                    }
                }

                $nic_return{$int_name} = [ $values{recv_data}, $values{send_data} ];
            }
        }
    }

    return \%nic_return;

}

sub nic_module {

    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $lif_result;
            eval {
                $lif_result = cdot_lif($hostname);
            };
            plugin_log("DEBUG_LOG", "*DEBUG* cdot_lif: $@") if $@;

            if($lif_result){

                foreach my $lif (keys %$lif_result){

                    my $lif_value_ref = $lif_result->{$lif};
                    my @lif_value = @{ $lif_value_ref };

                    plugin_dispatch_values({
                            plugin => 'interface_lif',
                            plugin_instance => $lif,
                            type => 'if_octets',
                            values => [$lif_value[0], $lif_value[1]],
                            interval => '30',
                            host => $hostname,
                            });
                }
            }

            my $port_result;
            eval {
                $port_result = cdot_port($hostname);
            };
            plugin_log("DEBUG_LOG", "*DEBUG* cdot_port: $@") if $@;

            if($port_result){

                foreach my $port (keys %$port_result){

                    my $port_value_ref = $port_result->{$port};
                    my @port_value = @{ $port_value_ref };

                    plugin_dispatch_values({
                            plugin => 'interface_port',
                            plugin_instance => $port,
                            type => 'if_octets',
                            values => [$port_value[0], $port_value[1]],
                            interval => '30',
                            host => $hostname,
                            });
                }
            }

        }

        default {

            my $nic_result;
            eval {
                $nic_result = smode_nic($hostname);
            };
            plugin_log("DEBUG_LOG", "*DEBUG* smode_nic: $@") if $@;

            if($nic_result){

                foreach my $nic (keys %$nic_result){

                    my $nic_value_ref = $nic_result->{$nic};
                    my @nic_value = @{ $nic_value_ref };

                    plugin_dispatch_values({
                            plugin => 'interface',
                            plugin_instance => $nic,
                            type => 'if_octets',
                            values => [$nic_value[0], $nic_value[1]],
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
