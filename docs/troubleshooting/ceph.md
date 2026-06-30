# Ceph Troubleshooting Guide

## Overview

This guide provides systematic troubleshooting procedures for Ceph clusters in both bare-metal and Rook-Ceph deployments. Follow the flow-chart style approach: Symptom → Possible Causes → Diagnostic Commands → Resolution.

## 1. Cluster Health Issues

### Symptom: HEALTH_WARN or HEALTH_ERR
**Possible Causes:**
- MON quorum issues
- OSD down or out
- PGs stuck (inactive, unclean, undersized, degraded)
- Full or near-full OSDs
- Clock skew between nodes
- MDS daemon issues (for CephFS)
- RGW sync issues

**Diagnostic Commands:**
```bash
# Get detailed health
ceph health detail

# Check MON quorum
ceph quorum_status --format json-pretty

# Check OSD map
ceph osd tree
ceph osd stat
ceph osd down
ceph osd out
ceph osd find <osd-id>

# Check PG status
ceph pg stat
ceph pg dump_stuck inactive
ceph pg dump_stuck unclean
ceph pg dump_stuck undersized
ceph pg dump_stuck degraded
ceph pg dump_stuck stale

# Check OSD disk usage
ceph osd df
ceph osd df tree

# Check clock skew
ceph clock skew

# Check MGR status
ceph mgr services

# Check MDS status (if CephFS)
ceph fs status <fsname>

# Check RGW sync status (if applicable)
radosgw-admin sync status
```

**Resolution:**
- For MON issues: fix quorum (see MON section below)
- For OSD down: check disk, network, restart osd daemon
- For OSD out: check if intentionally marked out, then mark in
- For stuck PGs: identify cause (usually down/out OSDs, full OSDs) and fix
- For full cluster: add more OSDs or delete data
- For clock skew: fix NTP/chrony configuration
- For MDS issues: restart MDS daemons
- For RGW sync: check logs and restart rgw daemons

### Symptom: Slow Performance or High Latency
**Possible Causes:**
- OSD hardware issues (slow disk, network)
- Too many PGs per OSD (>200-300)
- Recovery/backfill consuming resources
- Pool misconfiguration (wrong crush rule, size)
- Client throttling
- Network congestion
- Insufficient OSD memory/CPU

**Diagnostic Commands:**
```bash
# Check current operations
ceph -w  # Watch live operations

# Check recovery status
ceph pg dump_stuck
ceph osd pool ls detail
ceph osd pool get <pool> size
ceph osd pool get <pool> min_size
ceph osd pool get <pool> crush_rule

# Check per-OSD load
ceph osd perf
ceph osd pool stats <pool>

# Check network
ceph network extract

# Check disk latency
iostat -x 1 5

# Check system resources
top -b -n 1 | head -20
vmstat 1 5

# Check crush rule
osd crush rule dump
```

**Resolution:**
- Replace failing hardware
- Adjust pg_num for pools (use pg calc)
- Temporarily limit recovery: `ceph osd set noscrub, nodeep-scrub` then reset after
- Adjust crush rules if needed
- Check client quota/limits
- Upgrade network infrastructure
- Add resources to OSD nodes

## 2. MON (Monitor) Issues

### Symptom: MON Quorum Lost
**Possible Causes:**
- Less than majority of MONs running
- Network partition between MONs
- MON clock skew > 0.05 seconds
- MON store corrupted
- Missing MON keys

**Diagnostic Commands:**
```bash
# Check quorum
ceph quorum_status --format json-pretty
ceph mon stat

# Check individual MON status
ceph mon dump

# Check MON logs
journalctl -u ceph-mon@<hostname> -f

# Check clock sync
chronyc tracking
chronyc sources -v

# Check MON store
ceph mon getmap -o /tmp/featuremap
monmaptool --print /tmp/featuremap

# Check network between MONs
ping <mon-other-ip>
nc -zv <mon-other-ip> 6789
nc -zv <mon-other-ip> 3300
```

**Resolution:**
- Start stopped MONs: `systemctl start ceph-mon@<hostname>`
- Fix network issues between MONs
- Synchronize clocks with NTP/chrony
- If MON store corrupted: remove failed MON and re-add
- Recreate MON if necessary (last resort)

### Symptom: MON Not Electing Leader
**Possible Causes:**
- Paxos starvation
- Disk I/O too slow
- Network issues preventing proposal exchange
- Monitor store corruption

**Diagnostic Commands:**
```bash
# Check MON latency
ceph tell mon.* injectargs '--mon-debug-dump-traces 1'

# Check disk I/O on MON hosts
iostat -x 1 5

# Check MON logs for election messages
journalctl -u ceph-mon@<hostname> | grep -i election

# Check network between MONs
tcpdump -i any port 6789 or port 3300 -w mon.pcap
```

**Resolution:**
- Move MON data to faster storage (SSD/NVMe)
- Fix network issues
- Restart MON daemons
- If persistent, consider rebuilding MON store from good MON

## 3. OSD (Object Storage Daemon) Issues

### Symptom: OSD Down
**Possible Causes:**
- Daemon crashed
- Disk failure
- Network disconnected
- Permission issues
- Resource exhaustion (OOM)

**Diagnostic Commands:**
```bash
# Check OSD status
ceph osd tree
ceph osd stat
ceph osd down

# Check OSD logs
journalctl -u ceph-osd@<id> -f

# Check system logs
dmesg | tail -20
grep -i osd /var/log/messages | tail -10

# Check disk status
smartctl -a /dev/sdX
lsblk
blkid

# Check network
ip addr show
ip link show
ethtool eth0

# Check OSD process
ps -ef | grep osd
```

**Resolution:**
- Restart OSD: `systemctl start ceph-osd@<id>`
- Replace failed disk
- Fix network connectivity
- Fix permissions on OSD data directory
- Address OOM killer (reduce other workloads, add RAM)

### Symptom: OSD Out (but not down)
**Possible Causes:**
- Marked out manually (`ceph osd out`)
- OSD failed heartbeat checks
- OSD too slow to respond
- OSD marked out during upgrade/repair

**Diagnostic Commands:**
```bash
# Check why OSD is out
ceph osd find <osd-id> | grep -A5 -B5 "weight"

# Check OSD heartbeat status
ceph tell osd.<id> injectargs '--osd-heartbeat-grace 20'

# Check OSD load
ceph osd perf | grep <osd-id>

# Check recent OSD history
ceph osd metadata <osd-id>
```

**Resolution:**
- If intentional: `ceph osd in <osd-id>`
- If due to failure: fix underlying issue then mark in
- If due to slowness: investigate performance issue
- If during wait for recovery: be patient

### Symptom: OSD Flapping (In/Out Repeatedly)
**Possible Causes:**
- Intermittent network issues
- Unstable disk/I/O
- Overloaded OSD (too many PGs)
- Clock skew causing false failure detection
- Insufficient memory

**Diagnostic Commands:**
```bash
# Monitor OSD state changes
ceph -w  # Watch for osd.* up/down messages

# Check system logs during flap times
journalctl -u ceph-osd@<id> --since "5 minutes ago"

# Check disk I/O during flap period
iostat -x 1 5

# Check network stability
ping -t <osd-host>

# Check OSD load
ceph osd dump | grep <osd-id>
```

**Resolution:**
- Fix intermittent network (cables, switches, NIC)
- Replace unstable disk
- Reduce load by adjusting PG count or adding OSDs
- Fix clock synchronization
- Add memory or reduce other workloads

### Symptom: OSD CrashLoop (Repeated Crashes)
**Possible Causes:**
- BlueFS corruption
- RocksDB corruption
- Incompatible kernel/module
- Hardware memory errors
- Bug in Ceph version

**Diagnostic Commands:**
```bash
# Check OSD crash logs
journalctl -u ceph-osd@<id> | grep -i crash
coredumpctl list | grep ceph-osd
coredumpctl info <pid>

# Check Bluestore/RocksDB logs
ls -la /var/lib/ceph/osd/ceph-<id>/
# Look for rocksdb.log, ceph.log

# Check kernel messages
dmesg | tail -50
dmesg | grep -i -e memory -e segfault -e hardware

# Check for mcelog
mcelog --dump

# Check Ceph version and known issues
ceph --version
```

**Resolution:**
- If BlueFS corruption: `ceph-osd -i <id> --mkfs --osd-data /var/lib/ceph/osd/ceph-<id> --osd-cluster-ceph --osd-uuid <uuid>` (will lose data on that OSD!)
- If RocksDB corruption: may need to recreate OSD (data loss)
- Fix kernel/module issues
- Replace faulty RAM (if ECC errors)
- Consider downgrading/upgrading Ceph version if bug suspected

## 4. PG (Placement Group) Issues

### Symptom: PGs Stuck Inactive
**Possible Causes:**
- No OSDs up for the PG's acting set
- Waiting for peer (OSD down/recovering)
- OSD weight set to 0
- Crush map incomplete

**Diagnostic Commands:**
```bash
# Find stuck PGs
ceph pg dump_stuck inactive

# Get details for one PG
ceph pg <pgid> query

# Check acting set for PG
ceph osd map <pool> <object-name>  # Use an object known to be in PG
# Or: ceph pg map <pgid>

# Check OSDs in acting set
ceph osd tree | grep <osd-id-from-map>

# Check crush map
osd crush tree
```

**Resolution:**
- Bring down OSDs back up
- Wait for recovery to complete if OSDs were recently restarted
- Adjust crush map if missing buckets/items
- Increase OSD weight if set to 0 incorrectly

### Symptom: PGs Stuck Unclean
**Possible Causes:**
- Waiting for recovery to complete
- Backfill in progress
- Inconsistent replicas detected
- Scrubbing in progress

**Diagnostic Commands:**
```bash
# Find unclean PGs
ceph pg dump_stuck unclean

# Check recovery status
ceph pg detail <pgid>

# Check recovery operations
ceph -w  # Look for recovery messages

# Check deep scrub status
ceph pg dump_stuck stale
```

**Resolution:**
- Wait for recovery/backfill to complete (can take hours/days)
- If stuck due to inconsistency, may need manual repair:
  ```bash
  ceph pg repair <pgid>
  # Or for inconsistent:
  ceph pg inconsistent <pgid> --format json-pretty
  ```

### Symptom: PGs Stuck Undersized
**Possible Causes:**
- Not enough replicas available (size not met)
- Waiting for degraded objects to recover

**Diagnostic Commands:**
```bash
# Find undersized PGs
ceph pg dump_stuck undersized

# Check PG details
ceph pg <pgid> query | grep -A10 -B10 "missing"

# Check OSD status for acting set
ceph osd map <pool> <object-name>
```

**Resolution:**
- Wait for undersized objects to recover
- If permanent loss, may need to mark objects as found-lost:
  ```bash
  ceph pg mark_unfound_lost <rg> <pool> <pgid> --yes-i-really-mean-it
  ```

## 5. CephFS Issues

### Symptom: MDS Daemon Crashing or Not Starting
**Possible Causes:**
- Metadata corruption
- Incompatible clients
- Insufficient resources
- Configuration errors

**Diagnostic Commands:**
```bash
# Check MDS status
ceph fs status <fsname>

# Check MDS logs
journalctl -u ceph-mds@<hostname> -f

# Check MDS map
ceph mds stat

# Check for slow requests
ceph tell mds.* injectargs '--mds-debug-slow-threshold 0.1'
```

**Resolution:**
- Restart MDS: `systemctl restart ceph-mds@<hostname>`
- If corruption: may need to repair filesystem (offline)
- Check client versions
- Increase resources
- Fix configuration

### Symptom: Clients Cannot Mount CephFS
**Possible Causes:**
- MDS not available
- Authentication failure
- Network issues
- Client missing ceph.conf or keyring
- Firewall blocking ports

**Diagnostic Commands:**
```bash
# Check MDS availability
ceph fs status <fsname>
ceph mds stat

# Check client logs
dmesg | grep -i ceph
journalctl -u ceph.target -f  # For systemd-mounted

# Check mount command
mount -t ceph <mon-ip>:6789:/ /mnt -o name=admin,secretfile=/etc/ceph/ceph.client.admin.keyring

# Check network
telnet <mon-ip> 6789
telnet <mds-ip> 6800  # MDS ports

# Check authentication
ceph auth get client.admin
```

**Resolution:**
- Start MDS daemons
- Fix authentication (copy correct keyring)
- Fix network/firewall
- Provide correct ceph.conf and keyring to client
- Mount with correct options

## 6. RGW (RADOS Gateway) Issues

### Symptom: RGW Daemon Crashing
**Possible Causes:**
- Configuration errors
- Database corruption (if using DB backend)
- Civetweb issues
- Memory leaks
- Invalid requests

**Diagnostic Commands:**
```bash
# Check RGW status
radosgw-admin service status

# Check RGW logs
journalctl -u ceph-radosgw@rgw.<hostname> -f

# Check system logs
dmesg | tail -20

# Check Civetweb/beast logs
```

**Resolution:**
- Restart RGW: `systemctl restart ceph-radosgw@rgw.<hostname>`
- Fix configuration
- Check disk space
- Look for problematic requests in logs
- Consider upgrading/downgrading version

### Symptom: RGW Sync Failed (Multi-site)
**Possible Causes:**
- Network between sites
- RGW daemon not running on one side
- Credentials expired/wrong
- Bucket index corruption
- Shard locking issues

**Diagnostic Commands:**
```bash
# Check sync status
radosgw-admin sync status

# Check sync error logs
radosgw-admin sync error list
radosgw-admin sync error get <error-id>

# Check realm configuration
radosgw-admin realm get
radosgw-admin realm list

# Check period status
radosgw-admin period status
radosgw-admin period list

# Check specific zonegroup/zone
radosgw-admin zonegroup get --rgw-zonegroup=<id>
radosgw-admin zone get --rgw-zone=<id>

# Check logs on both sides
ssh <rgw-host-other-site> "journalctl -u ceph-radosgw@rgw.<hostname> -f"
```

**Resolution:**
- Fix network connectivity between sites
- Ensure RGW daemons running on all sites
- Refresh/regenerate credentials
- Check and fix bucket index if needed
- Restart RGW daemons to clear locks
- Reset period if needed (last resort)

### Symptom: Slow RGW Performance
**Possible Causes:**
- Overloaded RGW instances
- Slow Ceph cluster backend
- Inefficient request patterns
- Missing optimizations (curl, keepalive)
- Incorrect tiering settings

**Diagnostic Commands:**
```bash
# Check RGW load
radosgw-admin top
radosgw-admin top reads
radosgw-admin top writes

# Check Ceph cluster performance
ceph -w
ceph osd perf
ceph pg stat

# Check system resources
top -b -n 1
iostat -x 1 5

# Check network
netstat -i | grep -i rgw
```

**Resolution:**
- Add more RGW instances (scale horizontally)
- Fix backend Ceph performance issues
- Optimize application requests (use bulk operations)
- Enable HTTP keepalive in clients
- Review tiering/archive policies

## 7. CRUSH Map Issues

### Symptom: Data Not Distributing Evenly
**Possible Causes:**
- Incorrect crush rule
- Wrong device weights
- Missing buckets/topology
- Straw2 vs tunables issues

**Diagnostic Commands:**
```bash
# Check crush rule
osd crush rule dump
osd crush rule show <rule-name>

# Check device weights
ceph osd tree
ceph osd getcrushmap -o /tmp/out
crushtool -i /tmp/out --dump

# Check straw version
ceph osd get-tunables

# Test crush mapping
osdcrushmap -i /tmp/out --test --rep-show-removed --pool <pool> -p 1000
```

**Resolution:**
- Adjust crush rule to match desired hierarchy
- Set correct weights on devices/buckets
- Add missing buckets (host, rack, row, etc.)
- Update tunables if needed (careful with existing data)

### Symptom: Monitor Complains About Crush Map
**Possible Causes:**
- Inconsistent map versions
- Corrupted map
- Invalid tunables for current ceph version

**Diagnostic Commands:**
```bash
# Check mon map
monstat
monmaptool --print /var/lib/ceph/mon/ceph-a/store.monmap

# Check osd map for complaints
ceph health detail
```

**Resolution:**
- Ensure all mons and osds agree on map version
- Rewrite map if necessary (last resort)
- Adjust tunables to compatible values

## 8. Disk/Device Issues

### Symptom: Disk Failure Predicted by SMART
**Possible Causes:**
- Impending hardware failure
- Bad sectors
- Overheating
- Power issues

**Diagnostic Commands:**
```bash
# Check SMART status
smartctl -a /dev/sdX
smartctl -H /dev/sdX  # Health check only

# Check for pending sectors
smartctl -A /dev/sdX | grep -i "pending\|realloc\|seek"

# Check temperature
smartctl -A /dev/sdX | grep -i temperature

# Check power cycles
smartctl -A /dev/sdX | grep -i "power_on\|power_cycle"
```

**Resolution:**
- Backup data immediately
- Replace disk
- Re-add OSD with new disk
- Let Ceph rebalance

### Symptom: Intermittent I/O Errors
**Possible Causes:**
- Loose cables
- Failing controller
- Power fluctuations
- Kernel/driver issues

**Diagnostic Commands:**
```bash
# Check kernel logs
dmesg | tail -50
dmesg | grep -i -e ata -e scsi -e sd -e nvme

# Check SMART self-test
smartctl -t long /dev/sdX
# Wait, then:
smartctl -l selftest /dev/sdX

# Check i/o statistics during errors
iostat -x 1 10

# Check multipath (if used)
multipath -ll
```

**Resolution:**
- Check and reseat cables
- Replace SATA/SAS controller if needed
- Check power supply
- Update firmware/drivers
- Consider using enterprise-grade drives for OSDs

## 9. Network Issues

### Symptom: High Latency Between Nodes
**Possible Causes:**
- Network congestion
- Faulty switch/router
- Misconfigured QoS
- MTU mismatch
- Cable issues

**Diagnostic Commands:**
```bash
# Check latency
ping <other-node-ip>
ping -i 0.2 <other-node-ip>  # Faster ping

# Check packet loss
ping -c 100 <other-node-ip>

# Check route
tracepath <other-node-ip>
traceroute <other-node-ip>

# Check interface errors
ip -s link show <interface>
ethtool -S <interface>

# Check for duplex mismatch
ethtool <interface>

# Check switch port status
# (Requires access to switch management)
```

**Resolution:**
- Fix network congestion (QoS, VLANs)
- Replace faulty network equipment
- Ensure consistent MTU (usually 9000 for jumbo frames)
- Replace faulty cables
- Fix duplex mismatches

### Symptom: Intermittent Connectivity
**Possible Causes:**
- Spanning tree issues
- Flapping interfaces
- IP conflicts
- DHCP problems
- ARP issues

**Diagnostic Commands:**
```bash
# Monitor interface flaps
ip -s link show <interface> | grep -i "dropped\|overruns"

# Check ARP table
ip neigh show

# Look for duplicate IPs
arp-scan --localnet

# Check spanning tree status (switch logs)
# Check for BPDU guard events

# Monitor syslog for network messages
journalctl -u NetworkManager -f
```

**Resolution:**
- Fix spanning tree configuration
- Replace flapping NIC or cable
- Resolve IP conflicts
- Fix DHCP server/client
- Clear arp cache if needed: `ip neigh flush dev <interface>`

## 10. Log Locations and Debugging

### Where to Find Logs
```bash
# Ceph daemons (systemd)
journalctl -u ceph-*
journalctl -u ceph-mon@*.service
journalctl -u ceph-osd@*.service
journalctl -u ceph-mds@*.service
journalctl -u ceph-radosgw@*.service

# Ceph logs in /var/log/ceph/ (if using syslog fallback)
/var/log/ceph/ceph.log
/var/log/ceph/ceph.log.*.gz

# Specific daemon logs
/var/log/ceph/ceph-mon.a.log
/var/log/ceph/ceph-osd.0.log
/var/log/ceph/ceph-mds.0.log
/var/log/ceph/ceph-radosgw.0.log

# System logs
/var/log/messages
/var/log/syslog
/var/log/kern.log
/var/log/dmesg

# Container logs (if using containers)
docker ceph-daemon logs <container-name>
kubectl logs -n rook-ceph <pod-name>
```

### Increasing Debug Level
```bash
# Set debug level for specific subsystem
ceph tell osd.* injectargs '--osd-debug-ms 1'
ceph tell mon.* injectargs '--mon-debug-ms 1'
ceph tell mds.* injectargs '--mds-debug-ms 1'
ceph tell rgw.* injectargs '--rgw-debug-ms 1'

# Or via config (persistent)
ceph config set osd osd_debug_ms 1
ceph config set mon mon_debug_ms 1
# ... then restart daemons

# Remember to reset after debugging:
ceph config set osd osd_debug_ms 0
ceph config set mon mon_debug_ms 0
```

### Debugging Specific Issues
```bash
# Debug authentication
ceph auth get-or-create client.test mon 'allow r' osd 'allow *' -o /tmp/keyring
CEPH_ARGS='--id test --keyring /tmp/keyring' ceph -s

# Debug network connectivity
ceph tell mon.* injectargs '--mon_debug_tcp 1'
ceph tell osd.* injectargs '--osd_debug_tcp 1'

# Debug crush mapping
osd crush rule ls
osd crush rule dump
osd crush rule show <rulename>
echo "rule <rulename> steps take @bucket1 step choose firstn 0 type osd" | crushtool -t
```

## 11. Recovery Procedures

### Recovering from MON Store Loss
If you lose the MON store (e.g., disk failure):
```bash
# 1. Stop all MONs
systemctl stop ceph-mon@*

# 2. On one MON host (preferably the one with most recent data):
#    Extract monmap from OSDs
ceph mon getmap -o /tmp/oldmonmap.bin

# 3. Create new monmap
monmaptool --create --fsid <fsid> --add monA <mona-ip>:6789 \
  --add monB <monb-ip>:6789 --add monC <monc-ip>:6789 \
  --minmonquorum 2 --quorum 0,1,2 \
  /tmp/newmonmap.bin

# 4. Inject monmap into OSDs
ceph-mon -i mona --mkfs --monmap /tmp/newmonmap.bin --mon-data /var/lib/ceph/mon/mon-a

# 5. Start the first MON
systemctl start ceph-mon@mona

# 6. Wait for quorum, then add remaining MONs
ceph mon add monb <monb-ip>:6789
ceph mon add monc <monc-ip>:6789
```

### Recovering from OSD Data Loss
If you lose an OSD's data but the disk is still usable:
```bash
# 1. Mark OSD out (if not already)
ceph osd out <osd-id>

# 2. Wait for backfill to complete (ceph -w)

# 3. Zap the OSD disk
ceph-volume lvm zap /dev/sdX --destroy

# 4. Re-create OSD
ceph-volume lvm create --data /dev/sdX

# 5. Wait for rebalance to complete
```

### Fixing CRUSH Map After Node Replacement
```bash
# 1. Remove old OSD from crush
ceph osd crush remove osd.<old-id>

# 2. Remove old OSD from CRUSH map
ceph osd rm <old-id>

# 3. Add new OSD
ceph osd create <new-uuid> <new-id>

# 4. Add new OSD to crush
ceph osd crush add-bucket <new-host> host
ceph osd crush move <new-id> root=default host=<new-host>

# 5. Create OSD data dirs
ceph-volume lvm zap /dev/sdY --destroy
ceph-volume lvm create --data /dev/sdY

# 6. Start new OSD
systemctl start ceph-osd@<new-id>
```

## 12. Preventive Measures and Maintenance

### Daily Checks

#### Daily
```bash
# Check cluster health
ceph health
ceph -s  # Brief status

# Check for down/out OSDs
ceph osd down
ceph osd out
```

#### Weekly
```bash
# Check OSD tree
ceph osd tree

# Check PG distribution
ceph pg stat
ceph pg dump_stuck

# Check disk usage
ceph osd df
ceph osd df tree

# Check for slow ops
ceph tell osd.* injectargs '--osd-op-thread-timeout 0.5'  # Then check logs
```

#### Monthly
```bash
# Check scrub status
ceph detail scrub

# Check deep scrub status
ceph detail deep-scrub

# Review CRUSH map
osd crush tree
osd crush rule dump

# Check for outdated versions
ceph versions
ceph report

# Check daemon versions
ceph daemon mgr.A version
ceph daemon mon.a version
```

### Performance Tuning Guidelines
```bash
# Increase OP threads if needed (careful with memory)
ceph config set osd osd_op_threads 4
ceph config set osd osd_op_threads_su 2

# Adjust recovery speed (if not in hurry)
ceph config set osd osd_recovery_max_active 1
ceph config set osd osd_recovery_sleep 0
ceph config set osd osd_max_backfills 1

# Adjust scrub window (avoid peak hours)
ceph config set osd scrub_begin_hour 0
ceph config set osd scrub_end_hour 6

# Increase memory for RocksDB if needed
ceph config set osd rocksdb_block_cache_size 1073741824  # 1GB
```

## Emergency Contacts

- **Storage On-Call**: [Phone/Pager]
- **Network Team**: [Phone/Email]
- **Server/Hardware Team**: [Phone/Email]
- **Ceph Vendor Support**: [If applicable]
- **Database Team**: [If using Ceph for DB storage]

## Quick Reference: Common Ceph Commands

```bash
# Health and status
ceph health detail
ceph -s
ceph stat

# MON
ceph mon stat
ceph mon quorum_status
ceph mon dump

# OSD
ceph osd tree
ceph osd stat
ceph osd down
ceph osd out
ceph osd find <id>
ceph osd metadata <id>
ceph osd pool get <pool> size
ceph osd pool set <pool> size <num>

# PG
ceph pg stat
ceph pg dump_stuck [inactive|unclean|undersized|stale|degraded]
ceph pg <pgid> query
ceph pg map <pgid>

# Pools
ceph osd pool ls
ceph osd pool ls detail
ceph osd pool create <name> <pg_num> [<pgp_num>]
ceph osd pool delete <pool> <pool> --yes-i-really-really-mean-it

# CRUSH
osd crush tree
osd crush rule dump
osd crush rule show <name>
osd crush create-or-move-step --rule <rule> --pool <pool> --replicated-tier <tier> --take-asymptotic-size

# MDS
ceph fs status <name>
ceph mds stat

# RGW
radosgw-admin user list
radosgw-admin bucket list
radosgw-admin sync status
radosgw-admin log list --num 1

# Monitoring
ceph -w  # Watch live
ceph tell <daemon>.* injectargs --debug-ms 1  # Increase debug
ceph config show | grep -i debug
```