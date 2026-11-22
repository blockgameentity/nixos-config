# Overleaf database upgrade: Mongo 6.0 → 7.0, Redis 6.2 → 7.4

The module now defaults to `mongo:7.0` (`desu.images.mongo`) and
`redis:7.4-alpine` (`desu.images.redis`). Upstream Overleaf still pins 6.0/6.2, so
this is an intentional local deviation. It is safe because Overleaf speaks
`mongodb` node driver 6.12 and `ioredis` 4.27, both compatible with these servers.

## Tested here

Run against real containers, not assumed:

- MongoDB 6.0 data files were started with `mongo:7.0` (server 7.0.48): the seeded
  `sharelatex.projects` document survived, the replica set came up writable, and
  `featureCompatibilityVersion` reported `6.0` before and `7.0` after
  `setFeatureCompatibilityVersion`.
- The module's exact command (`--replSet overleaf`, no explicit `--bind_ip_all`) was
  reachable from a *second* container as `mongo:27017`, and `rs.initiate` with host
  `mongo:27017` worked.
- Redis 6.2.24 wrote a snapshot that `redis:7.4-alpine` (7.4.12) loaded with both
  keys and identical values.

Not tested: the third-party `rigon/sharelatex-full` image running against these
versions end-to-end. That is verified on the first real deployment.

## Fresh install on the new host (recommended)

Restore **logical** dumps into empty volumes:

1. `mongorestore --uri mongodb://localhost:27017 <dump>` into a Mongo 7.0 that has
   already initiated the `overleaf` replica set.
2. Overleaf Redis is a cache; do not restore it. Starting empty is expected and avoids
   stale lock/docupdater entries from the old host.
3. Verify `.deb`/login/compile, then `rs.status()` shows PRIMARY.

A fresh 7.0 database is created with FCV 7.0; no feature-compatibility step is needed.

## Upgrading an existing 6.0 data directory in place

Only when you copy physical `/data/db` files (not dumps) from a MongoDB 6.0 install:

```console
# 0. Logical backup first. Downgrades are NOT supported.
mongodump --uri mongodb://localhost:27017 --out /var/backups/mongo-pre-7

# 1. Stop Overleaf, then start Mongo 7 on the same data directory.
systemctl stop podman-overleaf.service
# switch desu.images.mongo to mongo:7.0 and redeploy, then:

# 2. 7.0 reads 6.0 files but keeps FCV 6.0 until you raise it.
podman exec overleaf-mongo mongosh --quiet --eval \
  'db.adminCommand({getParameter:1,featureCompatibilityVersion:1})'

podman exec overleaf-mongo mongosh --quiet --eval \
  'db.adminCommand({setFeatureCompatibilityVersion:"7.0",confirm:true})'

# 3. Start Overleaf and verify login + a PDF compile.
systemctl start podman-overleaf.service
```

If the replica set was initiated by 6.0, the member host string (`mongo:27017`) is
unchanged by the upgrade; the existing startup script only initiates an *uninitialised*
set, so it will not fight the restored configuration.

## Rollback

There is no in-place downgrade from 7.0. Recovery means restoring the `mongodump`
above into a `mongo:6.0` deployment. Keep that dump until the new host has been
verified in production.

## Redis

Redis holds session/docupdater state only; Overleaf rebuilds documents from Mongo.
The snapshot format is compatible (verified), but flushing is acceptable:

```console
podman exec overleaf-redis redis-cli flushall
```

Do that only while Overleaf is stopped, so no live updater loses state mid-session.
