# Semaphore

[Semaphore UI](https://semaphoreui.com/) runs `colinbruner/homelab-automation`
Ansible playbooks on a schedule (weekly `site.yml` apply, Sun 04:00).

- **Canonical runbook**: `docs/semaphore.md` in homelab-automation — read it
  before changing schedules or templates. Ops playbooks are never scheduled.
- **State**: SQLite on the `semaphore-data` PVC (`nfs-csi-buckets`). Single
  replica, `Recreate` strategy — SQLite is single-writer. (BoltDB is
  deprecated and panics at server start in v2.18.20.)
- **Secrets**: `OnePasswordItem` -> Secret `semaphore`
  (`op://lab/semaphore`). The pod's `OP_CONNECT_TOKEN` is read-only on the
  `lab` vault; playbook runs inherit `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` for
  `community.general.onepassword` lookups. `onepassword` lookups shell out to
  the `op` CLI on the controller (this pod), which the official image
  doesn't ship — an `install-op` init container copies it from
  `1password/op:2` into an `emptyDir` mounted at `/usr/local/bin/op`.
- **Auth**: local `admin` (bootstrap) + Pocket ID OIDC
  (`https://auth.colinbruner.com`). OIDC users are non-admin by default.
- **URLs**: https://semaphore.colinbruner.com (tunnel),
  https://semaphore-internal.colinbruner.com (LAN).
- **In-UI config** (Key Store, repository, environment, task templates,
  schedules, notifications) is manual — see the runbook.
