# ExamWatcher API runner compatibility

Inspected all five API workflow files. This was missing from the initial desktop-only review.

- `ci.yml`: Rust fmt/tests/migrations/environment checks use `ew-ci`; Postgres 18, Redis 7,
  RabbitMQ 3.12 service containers. Jobs run directly on the host runner (not Ubuntu job containers).
- `build-deploy.yml` and `stress-images.yml`: Buildx and local cache directories.
- `stress.yml`: manual load tests with a Kubernetes client configuration and cluster credentials.
- `runner-cleanup.yml`: persistent disk management.

Current workflows deliberately depend on `/var/lib/ew-ci-cache/{cargo,target,tools,docker}`,
root Cargo installations and persistent local caches. A disposable VM discards those paths,
and host bind-mounting them would both lose isolation and let jobs affect trusted releases.

**Decision:** retain the current trusted `ew-ci` runner for API workflows. Do not redirect
API jobs to `ci-public-x64` merely because it also has Docker. NixOS's disposable Linux guest
uses Docker, so the service-container model is available there for future untrusted jobs,
but API compatibility/caching and authorization have not been ported or tested.

For future public CI, create secret-free workflows with ephemeral service containers and
per-VM caches only. Keep publishing, stress-cluster credentials and release artifacts in
trusted workflows/runners. Do not share writable caches between contributor and release jobs.
