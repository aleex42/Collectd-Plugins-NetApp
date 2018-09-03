# --
# NetApp/Volume.pm - Collectd Perl Plugin for NetApp Storage Systems (Volume Module)
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp::VolumeDF;

use base 'Exporter';
our @EXPORT = qw(volume_df_module);

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

    my $output;
    eval {
        $output = connect_filer($hostname)->invoke_elem($api);
    };
    plugin_log(LOG_DEBUG, "*DEBUG* connect fail cdot_vol_df: $@") if $@;

    my $volumes = $output->child_get("attributes-list");

    if($volumes){

    my @result = $volumes->children_get();

        foreach my $vol (@result){

            my $vol_state_attributes = $vol->child_get("volume-state-attributes");

            if($vol->child_get("volume-state-attributes")){

                my $vol_info = $vol->child_get("volume-id-attributes");
                my $vol_name = $vol_info->child_get_string("name");

                unless(($vol_name =~ m/^temp-/) || ($vol_name =~ m/^temp__/) || ($vol_name =~/vol0/)){

                    if($vol_state_attributes->child_get_string("state") eq "online"){

                        my $vol_space = $vol->child_get("volume-space-attributes");

                        my $used = $vol_space->child_get_string("size-used");
                        my $free = $vol_space->child_get_int("size-available");

                        unless(defined($df_return{$vol_name})){

                            $df_return{$vol_name} = [ $used, $free ];

                            plugin_dispatch_values({
                                plugin => 'df_vol',
                                type => 'df',
                                type_instance => $vol_name,
                                values => [$used, $free],
                                interval => '30',
                                host => $hostname,
                            });
                        }
                    }
                }
            }
        }

        return \%df_return;

    } else {

        return undef;

    }
}

sub volume_df_module {

    my $hostname = shift;
    my $starttime = time();

    my $df_result;
    eval {
        $df_result = cdot_vol_df($hostname);
    };
    plugin_log(LOG_DEBUG, "*DEBUG* cdot_vol_df: $@") if $@;

    return 1;
}

1;

