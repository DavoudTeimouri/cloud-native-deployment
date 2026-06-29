# Ceph Cheat Sheet

> Quick reference for Ceph cluster operations

---

## Cluster Status

| Action | Command |
|--------|---------|
| Overall health | `ceph -s` |
| Health detail | `ceph health detail` |
| Health in JSON | `ceph health detail --format json` |
| Cluster status | `ceph status` |
| Ceph version | `ceph -v` |
| All daemon versions | `ceph versions` |
| Cluster usage | `ceph df` |
| Cluster usage detail | `ceph df detail` |
| PGs status | `ceph pg stat` |
| PGs by state | `ceph pg ls <state>` |
| OSD tree | `ceph osd tree` |
| OSD tree with weights | `ceph osd tree --format json` |
| OSD utilization | `ceph osd df` |
| OSD utilization tree | `ceph osd df tree` |
| OSD dump (full) | `ceph osd dump` |
| OSD perf | `ceph osd perf` |
| MON status | `ceph mon stat` |
| MON dump | `ceph mon dump` |
| MON quorum | `ceph mon quorum_status` |
| MGR dump | `ceph mgr dump` |
| MGR modules | `ceph mgr module ls` |
| CRUSH map dump | `ceph osd crush dump` |
| CRUSH map (readable) | `ceph osd getcrushmap -o map.bin && crushtool -d map.bin -o map.txt` |

---

## Pool Management

| Action | Command |
|--------|---------|
| List pools | `ceph osd pool ls` |
| List pools (detail) | `ceph osd pool ls detail` |
| Pool stats | `ceph osd pool stats` |
| Pool stats (specific) | `ceph osd pool stats <pool>` |
| Create replicated pool | `ceph osd pool create <pool> 128 128 replicated` |
| Create EC pool | `ceph osd pool create <pool> 128 128 erasure` |
| Set EC profile | `ceph osd erasure-code-profile set <profile> k=4 m=2` |
| Delete pool | `ceph osd pool rm <pool> <pool> --yes-i-really-really-mean-it` |
| Set pool size | `ceph osd pool set <pool> size 3` |
| Set min size | `ceph osd pool set <pool> min_size 2` |
| Set pg_num | `ceph osd pool set <pool> pg_num 256` |
| Set pgp_num | `ceph osd pool set <pool> pgp_num 256` |
| Get pool param | `ceph osd pool get <pool> size` |
| Set pool quota | `ceph osd pool set-quota <pool> max_bytes 100G` |
| Set pool application | `ceph osd pool application enable <pool> rbd` |
| Rename pool | `ceph osd pool rename <old> <new>` |
| Pool scrub | `ceph osd pool scrub <pool>` |
| Pool deep-scrub | `ceph osd pool deep-scrub <pool>` |

---

## RBD (RADOS Block Device)

| Action | Command |
|--------|---------|
| List images | `rbd ls <pool>` |
| List images (detail) | `rbd ls <pool> -l` |
| Create image | `rbd create <pool>/<image> --size 10G` |
| Create image with options | `rbd create <pool>/<image> --size 10G --image-feature layering` |
| Delete image | `rbd rm <pool>/<image>` |
| Resize image | `rbd resize <pool>/<image> --size 20G` |
| Info | `rbd info <pool>/<image>` |
| Map (attach) | `rbd map <pool>/<image>` |
| Map with options | `rbd map <pool>/<image> --id admin --keyring /etc/ceph/ceph.client.admin.keyring` |
| Unmap (detach) | `rbd unmap /dev/rbd/<pool>/<image>` |
| List mapped | `rbd showmapped` |
| Snapshot create | `rbd snap create <pool>/<image>@<snap>` |
| Snapshot list | `rbd snap list <pool>/<image>` |
| Snapshot rollback | `rbd snap rollback <pool>/<image>@<snap>` |
| Snapshot protect | `rbd snap protect <pool>/<image>@<snap>` |
| Snapshot unprotect | `rbd snap unprotect <pool>/<image>@<snap>` |
| Snapshot delete | `rbd snap rm <pool>/<image>@<snap>` |
| Clone from snapshot | `rbd clone <pool>/<parent>@<snap> <pool>/<child>` |
| Flatten clone | `rbd flatten <pool>/<child>` |
| Copy image | `rbd copy <pool>/<src> <pool>/<dst>` |
| Export image | `rbd export <pool>/<image> backup.img` |
| Import image | `rbd import backup.img <pool>/<image>` |
| Diff | `rbd diff <pool>/<image>` |

---

## CephFS

| Action | Command |
|--------|---------|
| List filesystems | `ceph fs ls` |
| Filesystem status | `ceph fs status` |
| Filesystem dump | `ceph fs dump` |
| Create filesystem | `ceph fs new <fsname> <metadata-pool> <data-pool>` |
| Set max MDS | `ceph fs set <fsname> max_mds 2` |
| MDS status | `ceph mds stat` |
| MDS fail | `ceph mds fail <id>` |
| Subvolume create | `ceph fs subvolume create <fsname> <subvol>` |
| Subvolume list | `ceph fs subvolume ls <fsname>` |
| Subvolume delete | `ceph fs subvolume rm <fsname> <subvol>` |
| Subvolume snapshot | `ceph fs subvolume snapshot create <fsname> <subvol> <snap>` |
| Subvolume snap rm | `ceph fs subvolume snapshot rm <fsname> <subvol> <snap>` |
| Snapshot create | `mkdir /mnt/cephfs/.snap/<snap>` |
| Snapshot delete | `rmdir /mnt/cephfs/.snap/<snap>` |
| Mount CephFS | `mount -t ceph <mon-ip>:6789:/ /mnt/cephfs -o name=admin,secret=<key>` |
| Mount (kernel) | `mount -t ceph <mon1>:6789,<mon2>:6789:/ /mnt/cephfs -o name=admin,secretfile=/etc/ceph/secret.key` |
| Scrub | `ceph fs scrub <fsname> start` |
| Scrub status | `ceph fs scrub <fsname> status` |

---

## RGW (RADOS Gateway)

| Action | Command |
|--------|---------|
| User create | `radosgw-admin user create --uid=<uid> --display-name="<name>"` |
| User list | `radosgw-admin user list` |
| User info | `radosgw-admin user info --uid=<uid>` |
| User modify | `radosgw-admin user modify --uid=<uid> --max-buckets=1000` |
| User rm | `radosgw-admin user rm --uid=<uid>` |
| Subuser create | `radosgw-admin subuser create --uid=<uid> --subuser=<subuid>` |
| Key create | `radosgw-admin key create --uid=<uid> --key-type=s3` |
| Key rm | `radosgw-admin key rm --uid=<uid> --key-type=s3` |
| Bucket list | `radosgw-admin bucket list` |
| Bucket stats | `radosgw-admin bucket stats --bucket=<bucket>` |
| Bucket rm | `radosgw-admin bucket rm --bucket=<bucket>` |
| Bucket link | `radosgw-admin bucket link --bucket=<bucket> --uid=<uid>` |
| Bucket unlink | `radosgw-admin bucket unlink --bucket=<bucket> --uid=<uid>` |
| Bucket index check | `radosgw-admin bi list --bucket=<bucket>` |
| Bucket reindex | `radosgw-admin bucket reindex --bucket=<bucket>` |
| Quota set | `radosgw-admin quota set --quota-scope=user --uid=<uid> --max-size=100G` |
| Quota enable | `radosgw-admin quota enable --quota-scope=user --uid=<uid>` |
| Usage show | `radosgw-admin usage show --uid=<uid>` |
| Usage trim | `radosgw-admin usage trim --uid=<uid>` |
| Sync status | `radosgw-admin sync status` |
| Metadata sync status | `radosgw-admin metadata sync status` |
| Zone get | `radosgw-admin zone get` |
| Zonegroup get | `radosgw-admin zonegroup get` |

---

## OSD Operations

| Action | Command |
|--------|---------|
| OSD list | `ceph osd ls` |
| OSD tree | `ceph osd tree` |
| OSD find | `ceph osd find <osd-id>` |
| OSD metadata | `ceph osd metadata <osd-id>` |
| OSD info | `ceph osd info <osd-id>` |
| OSD utilization | `ceph osd df` |
| OSD dump | `ceph osd dump` |
| OSD mark out | `ceph osd out <osd-id>` |
| OSD mark in | `ceph osd in <osd-id>` |
| OSD mark down | `ceph osd down <osd-id>` |
| OSD mark lost | `ceph osd lost <osd-id> --yes-i-really-mean-it` |
| OSD reweight | `ceph osd reweight <osd-id> 0.8` |
| OSD reweight by utilization | `ceph osd reweight-by-utilization` |
| OSD crush reweight | `ceph osd crush reweight osd.<id> 1.0` |
| OSD rm | `ceph osd rm <osd-id>` |
| OSD purge | `ceph osd purge <osd-id> --yes-i-really-mean-it` |
| OSD set noout | `ceph osd set noout` |
| OSD unset noout | `ceph osd unset noout` |
| OSD set noscrub | `ceph osd set noscrub` |
| OSD unset noscrub | `ceph osd unset noscrub` |
| OSD set nodeep-scrub | `ceph osd set nodeep-scrub` |
| OSD unset nodeep-scrub | `ceph osd unset nodeep-scrub` |
| OSD scrub | `ceph osd scrub <osd-id>` |
| OSD deep-scrub | `ceph osd deep-scrub <osd-id>` |
| OSD repair | `ceph osd repair <osd-id>` |
| OSD perf | `ceph osd perf` |
| OSD blocked-by | `ceph osd blocked-by` |
| OSD pool stats | `ceph osd pool stats <pool>` |
| BlueStore tool | `ceph-bluestore-tool show-label --dev /dev/sdX` |
| OSD restart | `systemctl restart ceph-osd@<osd-id>` |

---

## MON Operations

| Action | Command |
|--------|---------|
| MON status | `ceph mon stat` |
| MON dump | `ceph mon dump` |
| MON quorum status | `ceph mon quorum_status` |
| MON quorum enter | `ceph mon_quorum enter` |
| MON quorum exit | `ceph mon_quorum exit` |
| MON add | `ceph mon add <name> <ip>:port` |
| MON remove | `ceph mon remove <name>` |
| MON getmap | `ceph mon getmap -o /tmp/monmap` |
| MON features | `ceph mon feature ls` |

---

## MGR Operations

| Action | Command |
|--------|---------|
| MGR status | `ceph mgr stat` |
| MGR dump | `ceph mgr dump` |
| MGR module ls | `ceph mgr module ls` |
| MGR module enable | `ceph mgr module enable <module>` |
| MGR module disable | `ceph mgr module disable <module>` |
| MGR services | `ceph mgr services` |
| MGR fail | `ceph mgr fail <id>` |

**Common MGR Modules:**
- `dashboard` — Web UI
- `prometheus` — Metrics exporter
- `devicehealth` — Disk health monitoring
- `balancer` — Auto data rebalancing
- `rbd_support` — RBD management

---

## PG Operations

| Action | Command |
|--------|---------|
| PG stat | `ceph pg stat` |
| PG dump | `ceph pg dump` |
| PG dump (JSON) | `ceph pg dump --format json` |
| PG ls by state | `ceph pg ls <state>` |
| PG ls by pool | `ceph pg ls-by-pool <pool>` |
| PG ls by osd | `ceph pg ls-by-osd <osd-id>` |
| PG ls by primary | `ceph pg ls-by-primary <osd-id>` |
| PG query | `ceph pg <pg-id> query` |
| PG scrub | `ceph pg scrub <pg-id>` |
| PG deep-scrub | `ceph pg deep-scrub <pg-id>` |
| PG force-recovery | `ceph pg force-recovery <pg-id>` |
| PG force-backfill | `ceph pg force-backfill <pg-id>` |
| PG mark unfound lost | `ceph pg <pg-id> mark_unfound_lost delete` |
| PG repair | `ceph pg repair <pg-id>` |

**PG States:** `active`, `clean`, `degraded`, `recovering`, `backfill`, `remapped`, `stale`, `peering`, `incomplete`, `down`, `inconsistent`, `snaptrim`, `undersized`, `stuck`, `unknown`

---

## Troubleshooting Commands

| Action | Command |
|--------|---------|
| Health detail | `ceph health detail` |
| Health in JSON | `ceph health detail --format json-pretty` |
| PG dump stale | `ceph pg dump_stuck stale` |
| PG dump inactive | `ceph pg dump_stuck inactive` |
| PG dump unclean | `ceph pg dump_stuck unclean` |
| Slow ops | `ceph osd dump_slow_ops <osd-id>` |
| Slow requests | `ceph osd op_wip` |
| Find OSD for PG | `ceph map <pool> <object>` |
| Object info | `ceph osd map <pool> <object>` |
| Check perf | `ceph tell osd.<id> perf dump` |
| Dump mempools | `ceph daemon osd.<id> dump_mempools` |
| Dump hitsets | `ceph daemon osd.<id> dump_hitsets` |
| Dump transactions | `ceph daemon osd.<id> dump_ops_in_flight` |
| BlueStore allocator | `ceph daemon osd.<id> bluestore allocator dump block` |
| Set debug level | `ceph tell osd.<id> config set debug_osd 20/20` |
| Reset debug level | `ceph config rm osd debug_osd` |
| Config dump | `ceph config dump` |
| Config get | `ceph config get osd <key>` |
| Config set | `ceph config set osd <key> <value>` |
| Tell daemon | `ceph tell osd.<id> dump_slow_ops` |
| Admin socket | `ceph daemon osd.<id> help` |

---

## CRUSH Operations

| Action | Command |
|--------|---------|
| CRUSH dump | `ceph osd crush dump` |
| CRUSH rules | `ceph osd crush rule ls` |
| CRUSH rule dump | `ceph osd crush rule dump <rule>` |
| CRUSH tree | `ceph osd crush tree` |
| CRUSH class ls | `ceph osd crush class ls` |
| CRUSH device class set | `ceph osd crush set-device-class ssd osd.0` |
| CRUSH add bucket | `ceph osd crush add-bucket <name> <type>` |
| CRUSH move | `ceph osd crush move <bucket> <type>=<parent>` |
| CRUSH remove | `ceph osd crush remove <name>` |
| CRUSH reweight | `ceph osd crush reweight <name> 1.0` |
| CRUSH tunables | `ceph osd crush tunables <profile>` |
| CRUSH rule create | `ceph osd crush rule create-replicated <name> <root> <type> <class>` |
| CRUSH rule rm | `ceph osd crush rule rm <name>` |

---

## RBD Mirror

| Action | Command |
|--------|---------|
| Pool enable | `rbd mirror pool enable <pool> image` |
| Pool disable | `rbd mirror pool disable <pool>` |
| Pool peer add | `rbd mirror pool peer add <pool> <cluster>@<client>` |
| Pool peer rm | `rbd mirror pool peer rm <pool> <peer-uuid>` |
| Pool status | `rbd mirror pool status <pool>` |
| Image status | `rbd mirror image status <pool>/<image>` |
| Image enable | `rbd mirror image enable <pool>/<image> snapshot` |
| Image disable | `rbd mirror image disable <pool>/<image>` |
| Image resync | `rbd mirror image resync <pool>/<image>` |
| Pool info | `rbd mirror pool info <pool>` |
| Pool promote | `rbd mirror pool promote <pool>` |
| Pool demote | `rbd mirror pool demote <pool>` |
