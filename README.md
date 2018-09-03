# Collectd-Plugins-NetApp

## About 

New, better and faster version of "netapp-cdot-collectd".
(https://github.com/aleex42/netapp-7mode-collectd / https://github.com/aleex42/netapp-cdot-collectd).

Support only for "new" <b>NetApp Clustered Data ONTAP</b>.

You need the NetApp Manageability SDK in "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp".
I recommend a symlink from the current version to this folder. For example:

"/usr/lib/netapp-manageability-sdk-5.4/lib/perl/NetApp" -> "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp"


## Examples 

For detailed documentation and examples have a look at my Mediawiki:

* http://wiki.krogloth.de/index.php/NetApp_cDOT/Capacity_Management 
* http://wiki.krogloth.de/index.php/NetApp_7-Mode/Capacity_Management

## Modules

* CPU: CPU Busy (unit is "percent", even if "jiffies" is shown)
* Aggr: Aggregate Space Usage and IOPs
* Volume: Volume Space Usage, IOPs, Latency and Traffic
* NIC: Network Interface Traffic
* FCP: Fibre Channel HBA traffic
* FlashCache: FlashCache (also NVMe) stats
* Flash: FlashPool stats
* Disk: Disk Busy per Aggregate

## Configuration:

* Config File (/etc/collectd/sample-collectd.conf)

* Credentials File (/etc/collectd/netapp.ini)

## Custom Types:

Disk Busy, Flash Pool Hit-Ratio and Volume Latency are using custom RRDtool-Types.

For more information see the custom-types.db

# Contact / Author

Alexander Krogloth
<git at krogloth.de>
<alexander.krogloth at noris.de> for the noris network AG.

# License

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
