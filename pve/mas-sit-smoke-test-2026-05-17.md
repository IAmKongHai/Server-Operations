# mas-sit smoke test - 2026-05-17

## Scope

Validate the new `mas-sit` VM, runner, local Docker build path, and current application runtime state without mutating the reference SQL Server schema/data.

## Infrastructure

| Check | Result |
| --- | --- |
| VM | `130 / mas-sit` running |
| IP | `192.168.2.22/24` |
| SSH | `ec2-user@192.168.2.22` works |
| OS | Amazon Linux 2023.10.20260105 |
| Docker | `25.0.14` |
| Compose | `v2.24.5` |
| Runner | GitHub Actions runner `mas-sit` online |
| Runner group | `cypressoai` org runner group `mas-sit`, selected repos only |

## Network

| Check | Result |
| --- | --- |
| GitHub | VM can reach `https://github.com` |
| GHCR | VM can reach `https://ghcr.io/v2/` |
| Docker Hub | VM pulled `hello-world`, `node:24-alpine`, `nginx:1.27-alpine`, Go/Debian base images |
| SQL Server port | VM can connect to `192.168.2.20:1433` |
| Tailscale route | `192.168.2.16/28` appears in PVE `AllowedIPs` and `PrimaryRoutes` |

## Application Build

| Component | Result |
| --- | --- |
| Backend Docker build | Succeeded as `icare/backend:mas-sit-test` |
| Frontend Docker build | Succeeded as `icare/mas-portal:mas-sit-test` |
| Frontend Node version | Docker build uses `node:24-alpine` |
| SQL backup | Three DB backups created before migration |
| Backend migrate + seed | Completed after user approval |

## Runtime

| Check | Result |
| --- | --- |
| Backend DB connection | Container logs show successful connections to `medicalassistance` and `maswebkit` on `192.168.2.20` |
| Backend health | `http://127.0.0.1:8080/healthz` returns OK; Docker health is `healthy` |
| Frontend health | `http://127.0.0.1:5174/healthz` returns `ok` on VM |
| LAN frontend health | `http://192.168.2.22:5174/healthz` returns `ok` from local machine |
| LAN frontend API proxy | `http://192.168.2.22:5174/api/v1/health` returns HTTP 200 |
| Frontend external bind | `0.0.0.0:5174->80/tcp` for current test container |

## Rollback Points

- VM `110` PVE snapshot: `before-mas-go-migrate-20260517`.
- SQL backups: `/restore/backups/mas-sit-before-migrate-20260517-2334/`.
- VM `130` deploy-ready snapshot: `mas-sit-deploy-ready-20260517`.

## Safety Notes

- Database schema/data mutation was performed only after explicit user approval.
- Backend and frontend test containers remain running for UI/API reachability on `192.168.2.22:5174`.
- Future backend deployments run migrate + seed automatically through a temporary `docker compose run --rm seed` container.
