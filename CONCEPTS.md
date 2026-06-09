# Concepts

Shared domain vocabulary for this project - entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## mac-mini SonarQube CI

### mac-mini-sonar runner
A named pool of four GitHub Actions self-hosted runner service instances on `mac-mini` used by iCare SonarQube analysis jobs.

Each runner instance owns its own service environment, work folder, temporary directory, and local tool-cache slot. A fix to PATH, work folder depth, or local tool availability is not complete until all four service instances have been updated and restarted.

### runner slot
One physical member of the `mac-mini-sonar runner` pool, identified by its runner number and its corresponding short work folder.

Slot-local caches are independent: a Scanner CLI cache hit on one slot does not prove another slot is warm. Cache verification for this pool needs either a hit log per slot or a confirmed `.complete` marker in each slot's tool cache.
