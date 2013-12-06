Collectd-Plugins-NetApp
=======================

<b>NetApp Modules for Collectd Perl Plugin.</b>

New, better and faster version of "netapp-7mode-collectd" and "netapp-cdot-collectd".
(https://github.com/aleex42/netapp-7mode-collectd / https://github.com/aleex42/netapp-cdot-collectd).

Support for both <b>NetApp 7-Mode</b> and <b>NetApp Clustered Data ONTAP</b>.

You need the NetApp Manageability SDK in "/usr/lib/netapp-manageability-sdk-5.1/lib/perl/NetApp".

-- 

<b>Currently supported modules:</b>

    * CPU
      CPU Busy (unit is "percent", even if "jiffies" is shown)
      
    * Aggr (in work)
      Aggregate Space Usage and IOPs

    * Volume (in work)
      Volume Space Usage, IOPs, Latency and Traffic

    * NIC
      Network Interface Traffic

    * Disk (in work)
      Disk Busy per Aggregate

    * Flash Pool Hit-Ratio
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
