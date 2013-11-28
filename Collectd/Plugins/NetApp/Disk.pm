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

use feature qw(switch);

use Collectd qw( :all );
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
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

    my $out = connect_filer($hostname)->invoke_elem($in);

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

    open(FILE, ">/tmp/output.txt");
    use Data::Dumper;
    print FILE Dumper(%max_percent);
    close(FILE);

        return \%max_percent;
    } else {
        return undef;
    }
}


sub cdot_disk {
    
    my $hostname = shift;

}

sub disk_module {
   
    my ($hostname, $filer_os) = @_;

    given ($filer_os){

        when("cDOT"){

            my $disk_result = cdot_disk($hostname);

            if($disk_result){

                foreach my $aggr (keys %$disk_result){

                    my $aggr_value = $disk_result->{$aggr};

                    plugin_dispatch_values({
                            plugin => 'disk_busy',
                            type => 'netapp_disk_busy',
                            type_instance => $aggr,
                            values => [$aggr_value],
                            interval => '30',
                            host => $hostname,
                            });
                }
            }
        }

        default {

            my $disk_result = smode_disk($hostname);

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
                            });
                }
            }
        }
    }

    return 1;
}

1;

