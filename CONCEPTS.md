# Concepts

Shared domain vocabulary for this project - entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## mac-mini iCare CI

### mac-mini-sonar runner
A named pool of four GitHub Actions self-hosted runner service instances on `mac-mini` used by iCare CI jobs such as SonarQube analysis and frontend tests.

Each runner instance owns its own service environment, work folder, temporary directory, and local tool-cache slot. A fix to PATH, work folder depth, or local tool availability is not complete until all four service instances have been updated and restarted.

### runner slot
One physical member of the `mac-mini-sonar runner` pool, identified by its runner number and its corresponding short work folder.

Slot-local caches are independent: a Scanner CLI cache hit on one slot does not prove another slot is warm. Cache verification for this pool needs either a hit log per slot or a confirmed `.complete` marker in each slot's tool cache.

## 代理服务器流量监控

### VPS Traffic Monitor
A planned standalone Docker service on `mac-mini` for monitoring proxy VPS traffic on `tizi` and `rao-tizi`.

It reads existing `vnstat` data over SSH, calculates billing-cycle usage, shows an internal Web UI, and sends Telegram notifications when traffic or collection-failure thresholds are reached.

### billing reset day
The day of month when a VPS provider resets a server's traffic allowance.

For proxy traffic monitoring, this reset day defines the accounting cycle; calendar-month `vnstat -m` totals are not treated as authoritative when the provider's billing cycle starts on a different day.
