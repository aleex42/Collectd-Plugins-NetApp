package Collectd::Plugins::NetApp;

use strict;
use warnings;

use lib "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp";
use NaServer;
use NaElement;

use Data::Dumper;

use Collectd qw( :all );
use Config::Simple;

my $plugin_name = "NetApp";

my %hosts = ();

plugin_register(TYPE_CONFIG, $plugin_name, 'my_config');
plugin_register(TYPE_READ, $plugin_name, 'my_get');
plugin_register(TYPE_INIT, $plugin_name, 'my_init');

sub my_log {
        plugin_log shift @_, join " ", "$plugin_name", @_;
}

sub my_init {
    1;
}

sub my_config {

#    use Data::Dumper;
#    open(FILE, ">/tmp/output.txt");    

    my $config = shift;

    my @children = @{$config -> {children} };

    for my $host (@children){

        my $hostname;

        if($host->{key}){
            if($host->{key} eq "Host"){
                $hostname = $host->{values}->[0];
                for my $child (@{ $host->{children} }) {
                    if($child->{key} eq "Modules"){
                        my $modules = $child->{values};
                        my $count = scalar @{ $modules };
                        for my $i (0 ... $count-1){
                            push (@{$hosts{$hostname}},$modules->[$i]);
                        }
                    }
                }
            }
        }
    }
}

sub my_get {

        open(FILE, ">/tmp/output.txt");

    foreach my $hostname (keys %hosts){

        print FILE $hostname . "\n";

        my $ConfigFile = "/etc/collectd/netapp.ini";
        my $cfg = new Config::Simple($ConfigFile);

        my %Config = $cfg->vars();

        my $s = NaServer->new( $hostname, 1, 3 );
        $s->set_transport_type('HTTPS');
        $s->set_style('LOGIN');
        $s->set_admin_user( $Config{ $hostname . '.Username'}, $Config{ $hostname . '.Password'});

        my $output = $s->invoke("perf-object-instance-list-info-iter", "objectname", "system");

        my $nodes = $output->child_get("attributes-list");
        my @result = $nodes->children_get();

        foreach my $node (@result){

            my $node_uuid = $node->child_get_string("uuid");
            my @node = split(/:/,$node_uuid);
            my $node_name = $node[0];

            my $api = new NaElement('perf-object-get-instances');

            my $xi = new NaElement('counters');
            $api->child_add($xi);
            $xi->child_add_string('counter','cpu_busy');

            my $xi1 = new NaElement('instance-uuids');
            $api->child_add($xi1);

            $xi1->child_add_string('instance-uuid',$node_uuid);
            $api->child_add_string('objectname','system');

            my $xo = $s->invoke_elem($api);

            my $instances = $xo->child_get("instances");
            my $instance_data = $instances->child_get("instance-data");
            my $counters = $instance_data->child_get("counters");
            my $counter_data = $counters->child_get("counter-data");

            my $rounded_busy = sprintf("%.0f", $counter_data->child_get_int("value")/10000);

            plugin_dispatch_values({
                    plugin => 'cpu',
                    plugin_instance => $node_name,
                    type => 'cpu',
#                    type_instance => 'busy_percent',
                    values => [$rounded_busy],
                    interval => '30',
                    host => $hostname,
                    });
        }

        return 1;
    }

    close(FILE);
}

1;

