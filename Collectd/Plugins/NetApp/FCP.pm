# --
# NetApp/FCP.pm - Collectd Perl Plugin for NetApp Storage Systems (FCP Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::FCP;

use base 'Exporter';
our @EXPORT = qw(fcp_module);

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

sub cdot_fcp {

    my $hostname = shift;
    my %nic_return;
    my @nics;

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke("perf-object-instance-list-info-iter", "objectname", "fcp_lif");
    };
    plugin_log(LOG_DEBUG, "*DEBUG* connect fail cdot_fcp: $@") if $@;

    my $nics = $output->child_get("attributes-list");

    if($nics){

        my @result = $nics->children_get();
   
        foreach my $interface (@result){
    
            my $if_name = $interface->child_get_string("name");

            if($if_name =~ m/^lif_/){
                my $uuid = $interface->child_get_string("uuid");
                push(@nics, $uuid);
            }
        }

        my $api = new NaElement('perf-object-get-instances');
        my $xi = new NaElement('counters');
        $api->child_add($xi);
        $xi->child_add_string('counter','read_data');
        $xi->child_add_string('counter','write_data');
        my $xi1 = new NaElement('instance-uuids');
        $api->child_add($xi1);
    
        foreach my $nic_uuid (@nics){
            $xi1->child_add_string('instance-uuid',$nic_uuid);
        }
    
        $api->child_add_string('objectname','fcp_lif');
    
        my $xo;
        eval {
            $xo = connect_filer($hostname)->invoke_elem($api);
        };
        plugin_log(LOG_DEBUG, "*DEBUG* connect fail fcp nics: $@") if $@;

        my $instances = $xo->child_get("instances");
        if($instances){

            my @instance_data = $instances->children_get("instance-data");

            foreach my $nic (@instance_data){

                my $nic_name = $nic->child_get_string("name");

                #plugin_log(LOG_DEBUG, "--> $nic_name");

                my $counters = $nic->child_get("counters");
                if($counters){

                    my @counter_result = $counters->children_get();

                    my %values = (write_data => undef, read_data => undef);

                    foreach my $counter (@counter_result){

                        my $key = $counter->child_get_string("name");
                        if(exists $values{$key}){
                            $values{$key} = $counter->child_get_string("value");
                        }
                    }
#                    $nic_return{$nic_name} = [ $values{read_data}, $values{write_data} ];

                    plugin_dispatch_values({
                            plugin => 'fcp_lif',
                            plugin_instance => $nic_name,
                            type => 'if_octets',
                            values => [ $values{read_data}, $values{write_data}  ],
                            interval => '30',
                            host => $hostname,
                            #time => $starttime,
                            });
                    
                }
            }
        }
        return \%nic_return;
    } else {
        return undef;
    }
}

sub fcp_module {

    my ($hostname, $filer_os) = @_;
    my $starttime = time();

    given ($filer_os){

        when("cDOT"){

            my $lif_result;
            eval {
                $lif_result = cdot_fcp($hostname);
            };
            plugin_log(LOG_DEBUG, "*DEBUG* cdot_fcp: $@") if $@;

        }
    }

    return 1;
}

1;
