# Ceph Troubleshooting Guide

> Decision-tree style: **Symptom → Possible Causes → Diagnostic Commands → Resolution**

---

## 1. Health Checks & Status Interpretation

### Understanding Health States

| State | Meaning | Action |
|-------|---------|--------|
| `HEALTH_OK` | All checks pass | None |
| `HEALTH_WARN` | Degraded but functional | Investigate soon |
| `HEALTH_ERR` | Critical failure | Immediate action |

### Basic Health Commands
```bash
# Overall health
ceph -s
ceph health detail
ceph -v

# Full status
ceph status
ceph df
ceph osd tree
ceph mon stat
ceph mgr dump
```

---

## 2. Common Health Issues

### 2.1 Degenerate PGs

**Symptom:** `HEALTH_WARN: pgs degraded` — Placement Groups have incomplete replicas

**Possible Causes:**
- OSD down, data not fully replicated
- Recent OSD failure, recovery in progress
- `min_size` not met

**Diagnostic Commands:**
```bash
# Find degraded PGs
ceph pg dump | grep degenerate
ceph pg ls degraded

# Check which OSDs are affected
ceph osd tree
ceph osd dump | grep down

# Check PG states
ceph pg stat
ceph pg ls active+clean
ceph pg ls active+degraded
```

**Resolution:**
```bash
# If OSD is temporarily down, bring it back up
ceph osd lost <osd-id> --yes-i-really-mean-it  # ONLY if OSD is permanently gone

# Wait for recovery to complete
watch ceph -s

# If stuck, restart the affected OSD
systemctl restart ceph-osd@<osd-id>

# Check recovery progress
ceph pg dump | grep -E "active|degraded|recovering"
```

---

### 2.2 Unfound Objects

**Symptom:** `HEALTH_WARN: unfound objects` — Objects exist in PGs but not found on any OSD

**Diagnostic Commands:**
```bash
# List unfound objects
ceph pg ls unfound
ceph pg dump | grep unfound

# Check which PGs have unfound objects
ceph pg ls-by-pool <pool> unfound
```

**Resolution:**
```bash
# If objects are truly lost, mark them found (data loss!)
ceph pg <pg-id> mark_unfound_lost delete
# or for CephFS with rollback:
ceph pg <pg-id> mark_unfound_lost revert

# If it's a transient issue, wait for deep-scrub to resolve
ceph pg deep-scrub <pg-id>
```

---

### 2.3 Slow Ops

**Symptom:** `HEALTH_WARN: slow requests` — Operations taking too long

**Diagnostic Commands:**
```bash
# Check slow requests
ceph osd pool stats
ceph daemon osd.<id> dump_slow_ops
ceph daemon osd.<id> ops

# Check OSD performance
ceph osd perf

# Check disk IO on OSD nodes
ssh <osd-node> iostat -x 1 5
ssh <osd-node> iotop -o

# Check network between OSD nodes
ssh <osd-node> ping -c 10 <other-osd-node>
```

**Resolution:**
```bash
# Check for disk issues
ssh <osd-node> smartctl -a /dev/sdX

# Increase OSD op threads if CPU-bound
ceph tell osd.<id> config set osd_op_num_threads_per_shard 4

# Check for network congestion
ceph config set osd osd_heartbeat_interval 10
ceph config set osd osd_heartbeat_grace 30

# If specific OSD is slow, consider marking it out and reweighting
ceph osd reweight <osd-id> 0.5
```

---

### 2.4 Stuck PGs (Inactive/Unclean)

**Symptom:** PGs stuck in `inactive` or `unclean` state

**Diagnostic Commands:**
```bash
# Find stuck PGs
ceph pg ls inactive
ceph pg ls unclean
ceph pg ls stale

# Get PG details
ceph pg <pg-id> query

# Check acting set
ceph pg dump | grep <pg-id>
```

**Resolution:**
```bash
# Restart OSDs in the acting set
for osd in $(ceph pg <pg-id> query | jq -r '.acting[]'); do
  ssh <osd-node> systemctl restart ceph-osd@$osd
done

# If PG is stuck due to down OSD, mark it lost (last resort)
ceph osd lost <osd-id> --yes-i-really-mean-it

# Force PG recovery
ceph pg force-recovery <pg-id>
ceph pg force-backfill <pg-id>
```

---

### 2.5 OSD Down

**Symptom:** `HEALTH_WARN: 1 osd(s) down` in `ceph -s`

**Diagnostic Commands:**
```bash
# Check OSD status
ceph osd tree
ceph osd dump | grep -E "down|out|in"

# Check OSD logs
ssh <osd-node> journalctl -u ceph-osd@<osd-id> --since "10 minutes ago" --no-pager

# Check if OSD process is running
ssh <osd-node> ps aux | grep ceph-osd
ssh <osd-node> systemctl status ceph-osd@<osd-id>

# Check disk
ssh <osd-node> lsblk
ssh <osd-node> dmesg | grep -i "error\|fail" | tail -20
```

**Resolution:**
```bash
# Restart OSD
ssh <osd-node> systemctl restart ceph-osd@<osd-id>

# If OSD won't start, check disk
ssh <osd-node> ceph-volume lvm list
ssh <osd-node> ceph-bluestore-tool show-label --dev /dev/sdX

# If disk is dead, replace OSD (see section 5)
# If OSD is permanently gone
ceph osd out <osd-id>
ceph osd crush remove osd.<osd-id>
ceph auth del osd.<osd-id>
ceph osd rm <osd-id>
```

---

### 2.6 MON Down

**Symptom:** Monitor daemon down, quorum at risk

**Diagnostic Commands:**
```bash
# Check mon status
ceph mon stat
ceph mon dump
ceph mon quorum_status

# Check mon logs
ssh <mon-node> journalctl -u ceph-mon@<mon-id> --since "10 minutes ago" --no-pager

# Check mon disk
ssh <mon-node> df -h /var/lib/ceph/mon/
```

**Resolution:**
```bash
# Restart mon
ssh <mon-node> systemctl restart ceph-mon@<mon-id>

# If mon store is corrupted, rebuild from another mon
ssh <mon-node> rm -rf /var/lib/ceph/mon/ceph-<mon-id>
ceph-mon --cluster ceph --id <mon-id> --mkfs \
  --monmap /tmp/monmap \
  --keyring /tmp/ceph.mon.keyring
# Copy monmap and keyring from healthy mon first
ssh <healthy-mon> ceph mon getmap -o /tmp/monmap
scp <healthy-mon>:/tmp/monmap /tmp/
scp <healthy-mon>:/etc/ceph/ceph.mon.keyring /tmp/
ssh <mon-node> systemctl start ceph-mon@<mon-id>
```

---

## 3. CephFS Issues

### 3.1 MDS Stuck / Filesystem Degraded

**Symptom:** `ceph fs status` shows degraded, MDS in `up:replay` or `up:standby`

**Diagnostic Commands:**
```bash
# Check MDS status
ceph fs status
ceph mds stat
ceph fs dump

# Check MDS logs
ssh <mds-node> journalctl -u ceph-mds@<mds-id> --since "10 minutes ago" --no-pager

# Check CephFS health
ceph fs <fsname> health
```

**Resolution:**
```bash
# Restart MDS
ssh <mds-node> systemctl restart ceph-mds@<mds-id>

# If MDS is stuck in replay, force active
ceph fs set <fsname> max_mds 1
ceph mds fail <mds-id>

# Check for damaged metadata
ceph mds scrub /path damage
ceph mds repaired /path
```

---

### 3.2 CephFS Snapshot Issues

**Diagnostic Commands:**
```bash
# Check snapshots
ls -la /mnt/cephfs/.snap/
ceph fs subvolume snapshot ls <vol> <subvol>
```

**Resolution:**
```bash
# Remove stuck snapshot
rmdir /mnt/cephfs/.snap/<snapshot-name>
# or
ceph fs subvolume snapshot rm <vol> <subvol> <snap>
```

---

## 4. RGW (RADOS Gateway) Issues

### 4.1 Sync Failures (Multi-Site)

**Symptom:** Zone sync stuck, data not replicating between sites

**Diagnostic Commands:**
```bash
# Check sync status
radosgw-admin sync status
radosgw-admin sync status --source-zone=<zone> --destination-zone=<zone>

# Check metadata sync
radosgw-admin metadata sync status

# Check data sync
radosgw-admin data sync status --source-zone=<zone>

# Check zone/zonegroup config
radosgw-admin zone get
radosgw-admin zonegroup get
```

**Resolution:**
```bash
# Restart RGW
systemctl restart ceph-radosgw@rgw.<id>

# Restart sync
radosgw-admin sync restart

# Check for metadata conflicts
radosgw-admin metadata list bucket.instance
radosgw-admin metadata get bucket.instance:<id>

# Force full sync
radosgw-admin data sync init --source-zone=<zone>
radosgw-admin bucket sync init --bucket=<bucket> --source-zone=<zone>
```

---

### 4.2 Bucket Errors

**Diagnostic Commands:**
```bash
# Check bucket stats
radosgw-admin bucket stats --bucket=<bucket>

# Check bucket index
radosgw-admin bi list --bucket=<bucket>

# Check RGW logs
ssh <rgw-node> journalctl -u ceph-radosgw@rgw.<id> --since "10 minutes ago"
```

**Resolution:**
```bash
# Rebuild bucket index
radosgw-admin bi list --bucket=<bucket>  # check for errors
radosgw-admin bucket reindex --bucket=<bucket>

# Check for quota issues
radosgw-admin user info --uid=<user>
radosgw-admin quota set --quota-scope=user --uid=<user> --max-size=100G
```

---

## 5. RBD-Mirror Issues

### 5.1 Replication Lag

**Symptom:** Mirror images show `state: up+replaying` with high lag

**Diagnostic Commands:**
```bash
# Check mirror status
rbd mirror pool status <pool>
rbd mirror image status <pool>/<image>

# Check mirror daemon status
rbd mirror pool info <pool>

# Check daemon logs
ssh <node> journalctl -u ceph-rbd-mirror@<id> --since "10 minutes ago"
```

**Resolution:**
```bash
# Restart rbd-mirror daemon
systemctl restart ceph-rbd-mirror@<id>

# Check network between clusters
ping -c 10 <remote-monitor-ip>

# Resync specific image
rbd mirror image resync <pool>/<image>
```

---

### 5.2 Broken Mirror

**Symptom:** Mirror image in `up+error` state

**Resolution:**
```bash
# Force resync
rbd mirror image resync <pool>/<image>

# If resync fails, disable and re-enable
rbd mirror image disable <pool>/<image>
rbd mirror image enable <pool>/<image> snapshot

# Check peer connectivity
rbd mirror pool peer list <pool>
```

---

## 6. Performance Issues

### 6.1 Slow OSD Performance

**Diagnostic Commands:**
```bash
# Check OSD perf
ceph osd perf

# Check OSD utilization
ceph osd df tree

# Check BlueStore stats
ceph daemon osd.<id> bluestore allocator dump block

# Check network
ceph osd ping  # internal

# Check for scrub impact
ceph osd dump | grep -E "scrub|osd_scrub"
```

**Resolution:**
```bash
# Reduce scrub impact during peak hours
ceph config set osd osd_scrub_begin_hour 2
ceph config set osd osd_scrub_end_hour 6
ceph config set osd osd_scrub_during_recovery false
ceph config set osd osd_max_scrubs 1

# Tune BlueStore
ceph config set osd bluestore_cache_size_ssd 4294967296  # 4GB
ceph config set osd bluestore_prefer_deferred_size_ssd 0

# Check for slow disks
ceph tell osd.<id> dump_slow_ops
```

---

## 7. Disk/Device Issues & OSD Replacement

### 7.1 Failed OSD Disk Replacement Procedure

```bash
# 1. Mark OSD out
ceph osd out <osd-id>

# 2. Wait for rebalancing
watch ceph -s

# 3. Stop the OSD
ssh <osd-node> systemctl stop ceph-osd@<osd-id>
ssh <osd-node> systemctl disable ceph-osd@<osd-id>

# 4. Remove from CRUSH
ceph osd crush remove osd.<osd-id>

# 5. Remove auth
ceph auth del osd.<osd-id>

# 6. Remove OSD
ceph osd rm <osd-id>

# 7. Physically replace disk (or remap device)

# 8. Zap new disk
ceph-volume lvm zap /dev/sdX --destroy

# 9. Create new OSD
ceph-volume lvm create --data /dev/sdX

# 10. Verify
ceph osd tree
ceph -s
```

### 7.2 BlueStore Device Failure

```bash
# Check device health
ceph-bluestore-tool show-label --dev /dev/sdX

# If superblock is corrupted
ceph-bluestore-tool repair --dev /dev/sdX

# Check for FS issues on block device
xfs_repair -n /dev/sdX  # dry run first
xfs_repair /dev/sdX     # actual repair
```

---

## 8. Log Locations & Debug Levels

### Log Locations
| Component | Log Location |
|-----------|-------------|
| MON | `/var/log/ceph/ceph-mon.<id>.log` or `journalctl -u ceph-mon@<id>` |
| OSD | `/var/log/ceph/ceph-osd.<id>.log` or `journalctl -u ceph-osd@<id>` |
| MDS | `/var/log/ceph/ceph-mds.<id>.log` or `journalctl -u ceph-mds@<id>` |
| MGR | `/var/log/ceph/ceph-mgr.<id>.log` or `journalctl -u ceph-mgr@<id>` |
| RGW | `/var/log/ceph/ceph-client.rgw.<id>.log` |
| rbd-mirror | `journalctl -u ceph-rbd-mirror@<id>` |

### Increasing Debug Levels
```bash
# Temporary (runtime)
ceph tell osd.<id> config set debug_osd 20/20
ceph tell mon.<id> config set debug_mon 20/20
ceph tell mds.<id> config set debug_mds 20/20

# Persistent
ceph config set osd debug_osd 10/10
ceph config set mon debug_mon 10/10
ceph config set mds debug_mds 10/10

# Reset to default
ceph config rm osd debug_osd
ceph config rm mon debug_mon

# View current debug settings
ceph config dump | grep debug
```

---

## 9. Air-Gap Specific: Package Installation Failures

### 9.1 Ceph Packages from Nexus

**Symptom:** `apt-get install ceph` fails in air-gapped environment

**Diagnostic Commands:**
```bash
# Check Nexus repository configuration
cat /etc/apt/sources.list.d/ceph.list
cat /etc/apt/sources.list.d/nexus.list

# Test connectivity to Nexus
curl -I https://nexus.internal/repository/ceph-deb/
curl -I https://nexus.internal/repository/ceph-common/

# Check GPG key
apt-key list | grep -i ceph
```

**Resolution:**
```bash
# Add Nexus repository
echo "deb https://nexus.internal/repository/ceph-deb/ $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/ceph-nexus.list

# Add GPG key from Nexus
curl -fsSL https://nexus.internal/repository/keys/release.asc | apt-key add -

# Update and install
apt-get update
apt-get install -y ceph ceph-common

# If specific version needed
apt-get install ceph=18.2.2-1$(lsb_release -cs)1
```

---

## 10. Recovery Procedures

### Full Cluster Recovery from Backup
```bash
# 1. Stop all Ceph services
systemctl stop ceph.target

# 2. Restore MON stores from backup
# (Requires at least one healthy MON)
tar -xzf /backup/ceph-mon-backup.tar.gz -C /var/lib/ceph/mon/

# 3. Start MONs
systemctl start ceph-mon.target

# 4. Restore OSD data (if needed)
# Re-create OSDs from backup or re-balance

# 5. Verify
ceph -s
ceph health detail
```

### PG Recovery After Mass OSD Failure
```bash
# 1. Set noout flag to prevent data movement
ceph osd set noout

# 2. Bring OSDs back online one at a time
for osd in $(ceph osd tree | grep down | awk '{print $1}'); do
  systemctl start ceph-osd@$osd
  sleep 30
  ceph -s
done

# 3. Unset noout
ceph osd unset noout

# 4. Force recovery
ceph osd set norecover
ceph osd unset norecover

# 5. Monitor
watch ceph -s
```
