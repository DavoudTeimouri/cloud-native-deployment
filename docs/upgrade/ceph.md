# Ceph Upgrade Guide

## Overview

This guide covers upgrading Ceph clusters in an air-gapped environment. It applies to both bare-metal Ceph and Rook-Ceph deployments.

> **Important**: Always test upgrades in a non-production environment first. Ceph upgrades require careful planning due to storage data integrity concerns.

## Supported Upgrade Paths

Ceph follows a strict upgrade path: you can only upgrade to the next stable release (e.g., Quincy → Reef, Reef → Squid). Skipping releases is not supported.

Check the [Ceph release calendar](https://docs.ceph.com/en/latest/releases/) for current stable versions.

## Prerequisites

- Full cluster backup (or ability to recreate from backups)
- Ceph health check passed (HEALTH_OK)
- Adequate free space (>30% recommended)
- Network connectivity between all nodes
- Admin access to all Ceph nodes
- Air-gap: Updated Ceph packages in Nexus repository
- Maintenance window scheduled

## Phase 1: Pre-Upgrade Preparation

### 1.1 Verify Cluster Health

```bash
# Check overall health
ceph health detail

# Check OSD map
ceph osd tree

# Check MON quorum
ceph quorum_status --format json-pretty

# Check MGR status
ceph mgr stat

# Check OSD distribution
ceph osd df tree

# Check PG distribution
ceph pg dump_stuck inactive unclean undersized degraded
```

### 1.2 Backup Critical Configuration

```bash
# Backup Ceph configuration and keys
mkdir -p /root/ceph-backup-$(date +%Y%m%d)
cp /etc/ceph/ceph.conf /root/ceph-backup-$(date +%Y%m%d)/
cp /etc/ceph/ceph.client.admin.keyring /root/ceph-backup-$(date +%Y%m%d)/
# For cephadm:
ceph config config export > /root/ceph-backup-$(date +%Y%m%d)/ceph-config-$(date +%Y%m%d).txt
ceph config dump > /root/ceph-backup-$(date +%Y%m%d)/ceph-dump-$(date +%Y%m%d).txt
```

### 1.3 Verify OSD and MON Status

```bash
# All OSDs should be up and in
ceph osd status

# Check for down or out OSDs
ceph osd down
ceph osd out

# Check MONs
ceph mon stat

# Check MGRs
ceph mgr services
```

### 1.4 Check Available Space

```bash
# Ensure >30% free space for recovery operations
ceph df

# Check per-pool usage
ceph osd pool stats
```

### 1.5 Stop Client I/O (if possible)

For minimal risk, stop or drain client I/O during upgrade window:
```bash
# For Kubernetes with Ceph CSI:
# Scale down workloads or set to read-only
kubectl scale statefulset/db-app --replicas=0
# Or pause specific applications
```

### 1.6 Prepare Upgrade Packages

Ensure the target Ceph version is available in your Nexus repository:
```bash
# Example: Checking for Ceph Reef (v18.2.x)
apt-cache show ceph-common
 apt-cache policy ceph-base
```

## Phase 2: Bare-Metal Ceph Upgrade Procedure

### 2.1 Upgrade Monitor Nodes (First)

Upgrade MONs one at a time to maintain quorum:

```bash
# On each MON node, one at a time:
systemctl stop ceph-mon@$(hostname)

# Upgrade packages
apt update
apt install ceph-mon

# Verify version
ceph --version

# Start service
systemctl start ceph-mon@$(hostname)

# Wait for quorum to reform
ceph quorum_status --format json-pretty
# Wait until all MONs show as in quorum
```

### 2.2 Upgrade Manager Daemons

```bash
# On each MGR host, one at a time:
systemctl stop ceph-mgr@$(hostname)

# Upgrade packages
apt install ceph-mgr

# Start service
systemctl start ceph-mgr@$(hostname)

# Verify
ceph mgr services
```

### 2.3 Upgrade OSD Nodes (One at a Time)

This is the most critical step - upgrade OSDs one by one to maintain data availability:

```bash
# On each OSD host, one at a time:
# 1. Stop the OSD daemon
systemctl stop ceph-osd@*.service

# 2. Upgrade packages
apt install ceph-osd

# 3. Start the OSD daemon
systemctl start ceph-osd@*.service

# 4. Wait for OSD to come back in and reweight to 1.0
ceph osd tree | grep $(hostname)
# Look for the OSD(s) on this host - they should show 'up' and 'in'
# Check reweight becomes 1.0:
ceph osd dump | grep $(hostname) | grep ' weight '
```

> **Important**: Wait at least 5 minutes between OSD upgrades to allow rebalancing.

### 2.4 Upgrade MDS (if CephFS deployed)

```bash
# If using CephFS, upgrade MDS daemons one at a time:
systemctl stop ceph-mds@<filesystem_name>.*

# Upgrade
apt install ceph-mds

# Start
systemctl start ceph-mds@<filesystem_name>.*

# Verify
ceph fs status <filesystem_name>
```

### 2.5 Upgrade RGW (if deployed)

```bash
# For each RGW host, one at a time:
systemctl stop ceph-radosgw@rgw.* 

# Upgrade
apt install ceph-radosgw

# Start
systemctl start ceph-radosgw@rgw.*

# Verify
curl -s http://localhost:8080/health
```

### 2.6 Update Ceph Client Packages

On all clients (including Kubernetes nodes with Ceph CSI):
```bash
apt install ceph-common
# Verify ceph version matches cluster
ceph --version
```

## Phase 3: Rook-Ceph Upgrade Procedure

Rook-Ceph upgrades are handled via Helm chart upgrades, but require attention to the Ceph version compatibility matrix.

### 3.1 Check Rook-Ceph Version Compatibility

| Rook-Ceph Version | Supported Ceph Versions |
|-------------------|-------------------------|
| v1.8.x            | Octopus, Pacific        |
| v1.9.x            | Pacific, Quincy         |
| v1.10.x           | Quincy, Reef            |
| v1.11.x           | Reef, Squid             |
| v1.12.x           | Squid, Octopus (future) |

Always check [Rook compatibility matrix](https://rook.github.io/docs/rook/latest-release/CRDs/Cluster/CRD-CephCluster-spec/#ceph-version).

### 3.2 Pre-Upgrade Checks

```bash
# Check Rook operator status
kubectl -n rook-ceph get pods -l app=rook-ceph-operator

# Check CephCluster CR
kubectl -n rook-ceph get cephcluster -o yaml

# Check Ceph health via toolbox
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

### 3.3 Upgrade Rook Operator

```bash
# Update Helm repo (from Nexus)
helm repo update

# Check current version
helm list -n rook-ceph

# Upgrade to target version
helm upgrade rook-ceph rook-ceph/rook-ceph \
  --namespace rook-ceph \
  --version <target-rook-version> \
  --values rook-cepp-values.yaml \
  --wait
```

### 3.4 Trigger Ceph Upgrade (if needed)

If the Rook upgrade includes a Ceph version change, Rook will orchestrate the upgrade:
```bash
# Check if CephUpgrade CRD is present (Rook v1.11+)
kubectl get crd cephupgrades.ceph.rook.io

# If upgrading Ceph version, create CephUpgrade CR:
cat <<EOF | kubectl -n rook-ceph apply -f -
apiVersion: ceph.rook.io/v1
kind: CephUpgrade
metadata:
  name: upgrade
  namespace: rook-ceph
spec:
  version: "v18.2.0"  # Target Ceph version (e.g., Reef)
  image: harbor.internal/ceph/ceph:v18.2.0
  allowUnsafe: false
  # Optional: specify strategy
  # strategy:
  #   type: RollingUpdate
  #   rollingUpdate:
  #     maxUnavailable: 1
EOF

# Monitor progress
kubectl -n rook-ceph get cephupgrade -w
```

### 3.5 Post-Upgrade Verification

```bash
# Check Ceph version
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph version

# Verify all daemons are updated
kubectl -n rook-ceph get deploy,daemonset -l app=rook-ceph

# Check Ceph health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph health detail
```

## Phase 4: Post-Upgrade Validation

### 4.1 Health Checks

```bash
# Wait for cluster to return to HEALTH_OK
ceph health
# Should return HEALTH_OK after rebalancing completes

# Check for any lingering warnings
ceph health detail

# Monitor PG recovery
ceph pg stat
# Wait for active+clean state

# Check OSD map
ceph osd tree
# All OSDs should be 'up' and 'in'
```

### 4.2 Functionality Tests

```bash
# Test RADOS bench (if performance window allows)
rados bench -p .rgw.root 10 write --no-cleanup

# Test RBD image creation/map
rbd create test-image --size 1G --pool rbd
rbd map test-image --pool rbd --name client.admin
mkfs.ext4 /dev/rbd/rbd/test-image
mount /dev/rbd/rbd/test-image /mnt
# Write test file
umount /mnt
rbd unmap /dev/rbd/rbd/test-image
rbd rm test-image --pool rbd

# Test CephFS (if used)
ceph fs subvolume create cephfs test_subvol
ceph fs subvolume getpath cephfs test_subvol
# Mount via kernel or FUSE and test

# Test RGW
radosgw-admin user info --uid=testuser
```

### 4.3 Monitor Recovery Operations

```bash
# Watch recovery progress
watch -n 5 ceph -s

# Check recovery IOPS
ceph osd pool stats <pool-name> | grep recover

# Monitor backfill
ceph pg dump | grep -E 'backfill|recovery'
```

## Version-Specific Notes

### Quincy → Reef (v17 → v18)
- Major changes to CRUSH map tunables
- BlueStore improvements
- RGW timezone handling changes
- Required min_compat_client >= octopus

### Reef → Squid (v18 → v19)
- CephFS metadata improvements
- RGW object lifecycle enhancements
- RBD mirroring performance improvements
- Requires Debian 11/Ubuntu 22.04 or newer

## Rollback Procedure

> **Warning**: Downgrading Ceph is NOT supported and risks data loss. Always restore from backup if upgrade fails catastrophically.

### If Upgrade Fails Mid-Process

1. **Do not panic** - Ceph is designed to handle partial upgrades
2. **Identify failed component** (MON, MGR, OSD, etc.)
3. **Fix the specific issue** (usually package conflict or config incompatibility)
4. **Resume upgrade** from where it left off

### Recovery Steps for Common Failures

#### Failed MON Upgrade
```bash
# Check MON logs
journalctl -u ceph-mon@<hostname> -f

# Common fixes:
# 1. Config mismatch - compare with working MONs
# 2. Port conflict - check what's bound to 3300/6789
# 3. Disk space - /var/lib/ceph/mon needs space
```

#### Failed OSD Upgrade
```bash
# Check OSD logs
journalctl -u ceph-osd@<id> -f

# Common fixes:
# 1. Device not ready - check dmesg for hardware errors
# 2. BlueStore allocation issues - ensure sufficient space
# 3. SELinux/AppArmor - check audit logs
```

## Post-Upgrade Tasks

### 1. Update Client Ceph Packages
Ensure all ceph-common packages match cluster version.

### 2. Reset osd_max_backfills and osd_recovery_max_active
If you temporarily increased these for faster upgrade, return to defaults:
```bash
ceph config set osd osd_max_backfills 1
ceph config set osd osd_recovery_max_active 1
```

### 3. Clear Upgrade Flags
If you set any noout, nobackfill, etc flags for upgrade:
```bash
ceph osd unset noout
ceph osd unset nobackfill
ceph osd unset norecover
ceph osd unset noscrub
ceph osd unset nodeep-scrub
```

### 4. Validate Authentication
```bash
ceph auth list
# Verify all keys are present and correct
```

## Troubleshooting

### Slow Recovery
- Increase recovery ops temporarily: `ceph osd pool set <pool> recovery_max_active 3`
- Monitor network utilization between nodes
- Check disk I/O with `iostat -x 1`

### PGs Stuck Inactive
- Check for down OSDs: `ceph osd down`
- Check for full OSDs: `ceph osd df`
- Check MON logs for clock skew

### Monitor Quorum Loss
- Verify NTP sync: `chronyc tracking`
- Check network partition
- Review MON logs for election issues

## Maintenance Schedule Post-Upgrade

1. **Day 1**: Monitor closely, verify critical operations
2. **Day 2**: Check for any deferred alerts
3. **Week 1**: Verify backup procedures work with new version
4. **Month 1**: Review performance baselines, adjust if needed

## Appendix: Useful Commands

### Check Version Across Cluster
```bash
ceph versions
```

### Force Osd to Report In
```bash
ceph osd in <osd-id>
```

### Mark Osd Out (for maintenance)
```bash
ceph osd out <osd-id>
```

### Check Upgrade Status (cephadm)
```bash
ceph orch upgrade status
```

### View Upgrade History
```bash
ceph orch upgrade history
```