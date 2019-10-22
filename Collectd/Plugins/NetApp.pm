# --
# NetApp.pm - Collectd Perl Plugin for NetApp Storage Systems
# https://github.com/aleex42/Collectd-Plugins-NetApp
# Copyright (C) 2013 Alexander Krogloth, E-Mail: git <at> krogloth.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Collectd::Plugins::NetApp;

use strict;
use warnings;
no warnings "experimental";

use threads;

use Collectd::Plugins::NetApp::CPU qw(cpu_module);
use Collectd::Plugins::NetApp::Volume qw(volume_module);
use Collectd::Plugins::NetApp::VolumeDF qw(volume_df_module);
use Collectd::Plugins::NetApp::Aggr qw(aggr_module);
use Collectd::Plugins::NetApp::NIC qw(nic_module);
use Collectd::Plugins::NetApp::Disk qw(disk_module);
use Collectd::Plugins::NetApp::Flash qw(flash_module);
use Collectd::Plugins::NetApp::FlashCache qw(flashcache_module);
use Collectd::Plugins::NetApp::IOPS qw(iops_module);
use Collectd::Plugins::NetApp::NACommon qw(connect_filer);
use Collectd::Plugins::NetApp::FCP qw(fcp_module);

use feature qw/switch/;

use lib "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp";
use NaServer;
use NaElement;

use Data::Dumper;

use Collectd qw( :all );
use Config::Simple;

my @cdot_modules = ("CPU", "Aggr", "Volume", "VolumeDF", "NIC", "Disk", "Flash", "IOPS", "FlashCache", "FCP");

my $ConfigFile = "/etc/collectd/netapp.ini";
my $cfg = new Config::Simple($ConfigFile);
my %Config = $cfg->vars();

my $plugin_name = "NetApp";

plugin_register(TYPE_READ, $plugin_name, 'my_get');
plugin_register(TYPE_INIT, $plugin_name, 'my_init');
plugin_register(TYPE_CONFIG, $plugin_name, 'my_config');

sub my_config {
    1;
}

sub my_log {
#        plugin_log shift @_, join " ", "$plugin_name", @_;
}

sub my_init {
    1;
}

sub module_thread_func {

    my ($module, $hostname) = @_;

    my $starttime = time();

    $SIG{'KILL'} = sub { plugin_log(LOG_INFO, "*TIMEOUT* module $hostname/$module GOT KILLED") };

#    plugin_log(LOG_INFO, "*DEBUG*: module $hostname: $module");

    my $module_name = $module;

    given($module){

        when("CPU"){
                cpu_module($hostname);
        }

        when("Aggr"){
                aggr_module($hostname);
        }

    	when("Volume"){
        		volume_module($hostname);
    	}

        when("VolumeDF"){
                volume_df_module($hostname);
        }        

        when("NIC"){
            	nic_module($hostname);
        }

        when("Disk"){
        	disk_module($hostname);
        }

        when("Flash"){
                flash_module($hostname);
        }

        when("FlashCache"){
                flashcache_module($hostname);
        }

        when("FCP"){
                fcp_module($hostname);
        }

        when("IOPS"){
                iops_module($hostname);
        }

        default {
# nothing
        }
    }
    
    my $duration = time()-$starttime;

    plugin_log(LOG_INFO, "*DEBUG* finished thread $hostname/$module_name (duration: $duration)");
}

sub my_get {

    my @hosts = keys %{ $cfg->{_DATA}};
    my $timeout = 8;
    my @threads = ();

#    plugin_log(LOG_INFO, "*DEBUG* STARTED");
    my $start = time();

    foreach my $hostname (@hosts)  {

        foreach my $module (@cdot_modules){
            my $exclude = $Config{ $hostname . '.ExcludeModules'};

            if($exclude){

                $exclude=[$exclude] unless(ref($exclude) eq 'ARRAY');

                unless(grep(/$module/, @$exclude)){
                    my $thr = threads->create (\&module_thread_func, $module, $hostname);
                    push(@threads, $thr);
           		    plugin_log(LOG_INFO, "*DEBUG* new thread $hostname/$module: ".$thr->tid());
                }
            }
        }
    }

    sleep $timeout-(time()-$start);

    plugin_log(LOG_INFO, "*DEBUG* DETACHING ". threads->list(threads::joinable));
    foreach (threads->list(threads::joinable)) {
        plugin_log(LOG_INFO, "*DEBUG* joined finished trhead ".$_->tid());
        $_->join();
    }

    plugin_log(LOG_INFO, "*DEBUG* STILL RUNNING ". threads->list(threads::running));
    foreach (threads->list(threads::running)) {
        plugin_log(LOG_INFO, "*DEBUG* still running thread ".$_->tid());
        $_->kill('KILL');
        $_->detach();
    }

    plugin_log(LOG_INFO, "*DEBUG* FINISHED ");

    return 1;
}

1;

