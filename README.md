Collectd-Plugins-NetApp
=======================

<b>NetApp Modules for Collectd Perl Plugin.</b>

New, better and faster version of "netapp-7mode-collectd" and "netapp-cdot-collectd".
(https://github.com/aleex42/netapp-7mode-collectd / https://github.com/aleex42/netapp-cdot-collectd).

Support for both <b>NetApp 7-Mode</b> and <b>NetApp Clustered Data ONTAP</b>.

You need the NetApp Manageability SDK in "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp".
I recommend a symlink from the current version to this folder. For example:

"/usr/lib/netapp-manageability-sdk-5.4/lib/perl/NetApp" -> "/usr/lib/netapp-manageability-sdk/lib/perl/NetApp"

--

<b>Detailed Documentation / Examples</b>

For detailed documentation and examples have a look at my Mediawiki:

* http://wiki.krogloth.de/wiki/NetApp_C-Mode/Capacity_Management
* http://wiki.krogloth.de/wiki/NetApp_7-Mode/Capacity_Management

-- 

<b>Currently supported modules:</b>

    * CPU
      CPU Busy (unit is "percent", even if "jiffies" is shown)
      
    * Aggr
      Aggregate Space Usage and IOPs

    * Volume
      Volume Space Usage, IOPs, Latency and Traffic

    * NIC
      Network Interface Traffic

    * Disk (in work)
      Disk Busy per Aggregate

    * Flash Pool Hit-Ratio (currently only cDOT)
      Hit-Ratio (read/write) for Hybrid Aggregates
--

<b>Configuration:</b>

    * Config File (/etc/collectd/sample-collectd.conf)

    * Credentials File (/etc/collectd/netapp.ini)

--

<b>Custom Types:</b>

Disk Busy, Flash Pool Hit-Ratio and Volume Latency are using custom RRDtool-Types.

For more information see the custom-types.db

--
LICENSE AND COPYRIGHT

Copyright (C) 2013 Alexander Krogloth (noris network AG), E-Mail: git < at > krogloth.de

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published
by the Free Software Foundation.
