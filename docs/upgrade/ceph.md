# Ceph Upgrade Guide

> Rolling upgrade procedure for Ceph clusters

---

## 1. Pre-Upgrade Checks

### 1.1 Version Compatibility

```bash
# Check current Ceph version
ceph -v
ceph versions

# Verify upgrade path is supported
# Ceph supports N-1 version upgrades
# e.g., Reef (18.x) → Squid (19.x) is supported
# Check: https://docs.ceph.com/en/latest/releases/

# Check KubeSpray or cephadm version compatibility
cephadm version
```

### 1.2 Health Check

```bash
# Cluster must be HEALTH_OK before upgrade
ceph -s
ceph health detail

# If HEALTH_WARN, resolve before proceeding
# If HEALTH_ERR, DO NOT upgrade until resolved

# Check all OSDs are up
ceph osd tree
ceph osd dump | grep -E "down|out"

# Check all MONs in quorum
ceph mon stat
ceph mon quorum_status

# Check MDS health (if CephFS)
ceph fs status

# Check RBD mirror (if used)
rbd mirror pool status <pool>
```

### 1.3 Backup

```bash
# Backup Ceph configuration
ceph config dump > /backup/ceph-config-$(date +%Y%m%d).txt

# Backup CRUSH map
ceph osd getcrushmap -o /backup/crushmap-$(date +%Y%mdbg).bin
crushtool -d /backup/crushmap-$(date +%Y%m%d).bin -o /backup/crushmap-$(date +%Y%m%d).txt

# Backup pool configurations
ceph osd pool ls detail > /backup/pools-$(date +%Y%m%d).txt

# Backup RGW zone/zonegroup (if multi-site)
radosgw-admin zone get > /backup/zone-$(date +%Y%m%d).json
radosgw-admin zonegroup get > /backup/zonegroup-$(date +%Y%m%d).json
```

### 1.4 Set Upgrade Flags

```bash
 # Prevent unnecessary data movement during upgrade
ceph osd set noout
ceph osd set noscrub
ceph osd set nodeep-scrub
```

---

## 2. Rolling Upgrade Procedure

### 2.1 Upgrade Order

The correct upgrade order is:
1. **MONs** (one at a time)
2. **MGRs** (one at a time)
3. **OSDs** (one host at a time)
4. **MDSs** (if CephFS)
5. **RGWs** (if RGW)
6. **rbd-mirror** (if used)

### 2.2 Upgrade Using cephadm (Recommended)

```bash
# Set target version
ceph orch upgrade start --ceph-version 18.2.2

# Monitor upgrade progress
ceph orch upgrade status
ceph -s

# Check daemon status
ceph orch ps

# If upgrade stalls
ceph orch upgrade pause
ceph orch upgrade resume

# Stop upgrade if needed
ceph orch upgrade stop
```

### 2.3 Manual Upgrade (Without cephadm)

#### Upgrade MONs (one at a time)

```bash
# On first MON node
systemctl stop ceph-mon@<mon-id>

# Upgrade Ceph packages
apt-get update
apt-get install -y ceph-mon ceph-common

# Start MON
systemctl start ceph-mon@<mon-id>

# Verify quorum
ceph mon stat
ceph -s

# Wait before proceeding to next MON
sleep 30

# Repeat for each remaining MON
```

#### Upgrade MGRs (one at a time)

```bash
# On first MGR node
systemctl stop ceph-mgr@<mgr-id>

# Upgrade packages
apt-get install -y ceph-mgr ceph-common

# Start MGR
systemctl start ceph-mgr@<mgr-id>

# Verify
ceph mgr stat
ceph mgr dump

# Repeat for each MGR
```

#### Upgrade OSDs (one host at a time)

```bash
# Set OSD flags to prevent recovery
ceph osd set noout
ceph osd set noscrub
ceph osd set nodeep-scrub

# On first OSD host
# Mark OSDs out (optional, prevents data movement)
for osd in $(ceph osd ls-tree <hostname>); do
  ceph osd out $osd
done

# Wait for rebalancing
watch ceph -s

# Stop all OSDs on this host
systemctl stop ceph-osd.target

# Upgrade packages
apt-get update
apt-get install -y ceph-osd ceph-common

# Start OSDs
systemctl start ceph-osd.target

# Mark OSDs back in
for osd in $(ceph osd ls-tree <hostname>); do
  ceph osd in $osd
done

# Wait for recovery
watch ceph -s

# Verify all OSDs on this host are up
ceph osd tree | grep <hostname>

# Repeat for each OSD host
```

#### Upgrade MDSs (if CephFS)

```bash
# Fail over MDS
ceph mds fail <mds-id>

# On MDS node
systemctl stop ceph-mds@<mds-id>
apt-get install -y ceph-mds ceph-common
systemctl start ceph-mds@<mds-id>

# Verify
ceph fs status
```

#### Upgrade RGWs

```bash
# On RGW node
systemctl stop ceph-radosgw@rgw.<id>
apt-get install -y radosgw ceph-common
systemctl start ceph-radosgw@rgw.<id>

# Verify
radosgw-admin status
```

---

## 3. Post-Upgrade Verification

```bash
# Check new version
ceph -v
ceph versions

# Verify HEALTH_OK
ceph -s
ceph health detail

# Verify all daemons upgraded
ceph orch ps  # for cephadm
# or
ceph mon stat
ceph mgr dump
ceph osd tree

# Verify all OSDs are up and in
ceph osd dump | grep -E "down|out"

# Verify pools are accessible
ceph df
rados df

# Test RBD
rbd ls <pool>
rbd create <pool>/test --size 1G
rbd rm <pool>/test

# Test CephFS
ceph fs status
touch /mnt/cephfs/testfile
rm /mnt/cephfs/testfile

# Test RGW
radosgw-admin bucket list

# Re-enable scrubbing
ceph osd unset noscrub
ceph osd unset nodeep-scrub
ceph osd unset noout

# Run deep-scrub to verify data integrity
ceph osd scrub <osd-id>
ceph osd deep-scrub <osd-id>
```

---

## 4. Rollback Procedure

### 4.1 Rollback Using cephadm

```bash
# Stop upgrade in progress
ceph orch upgrade stop

# Downgrade packages on each node
apt-get install ceph-mon=17.2.6-0 ceph-osd=17.2.6-0 ceph-common=17.2.6-0

# Restart daemons
systemctl restart ceph.target

# Verify
ceph -s
ceph health detail
```

### 4.2 Manual Rollback

```bash
# Downgrade in reverse order: OSDs → MGRs → MONs

# On each OSD host
systemctl stop ceph-osd.target
apt-get install ceph-osd=<old-version>
systemctl start ceph-osd.target

# On each MGR
systemctl stop ceph-mgr@<id>
apt-get install ceph-mgr=<old-version>
systemctl start ceph-mgr@<id>

# On each MON
systemctl stop ceph-mon@<id>
apt-get install ceph-mon=<old-version>
systemctl start ceph-mon@<id>

# Verify
ceph -s
```

---

## 5. Version-Specific Considerations

### 5.1 Reef (18.x) to Squid (19.x)

```bash
# Check for deprecated OSD features
ceph osd dump | grep -E "ec_overwrites|purged_snaps"

# Verify BlueStore is default (FileStore removed)
ceph osd metadata <osd-id> | grep osd_objectstore

# Check for required OSD release
ceph osd require-osd-release squid
```

### 5.2 Performance Tuning After Upgrade

```bash
# New defaults may differ - review
ceph config dump | grep -E "osd_op|bluestore|filestore"

# Adjust if needed
ceph config set osd osd_op_num_threads_per_shard 4
ceph config set osd bluestore_cache_size_ssd 4294967296
```

---

## 6. Air-Gap Upgrade

### 6.1 Package Repository

```bash
# Ensure Nexus has new Ceph packages
curl -I https://nexus.internal/repository/ceph-deb/dists/reef/main/binary-amd64/Packages

# If not available, upload packages manually
# On internet-connected machine:
apt-get download ceph-mon ceph-osd ceph-mgr ceph-common ceph-mds radosgw
# Upload to Nexus repository

# Update apt cache
apt-get update
apt-cache policy ceph-osd  # verify new version available
```

### 6.2 Container Images (cephadm)

```bash
# Pull new cephadm image
docker pull quay.io/ceph/ceph:v18

# Push to Harbor
docker tag quay.io/ceph/ceph:v18 harbor.internal/library/ceph:v18
docker push harbor.internal/library/ceph:v18

# Update cephadm to use internal registry
ceph config set global container_image harbor.internal/library/ceph:v18
```
