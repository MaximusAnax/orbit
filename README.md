# orbit

A personal AI memory for relationships. Design ratified; **all six milestones (M0–M5) built and CI-green** on `feature/initial_build` — Linux core suite (ledger, pipeline, recall, search, export) and macOS iOS-app build + hosted tests both pass on every push. What's left is device bring-up on Abdoul's Mac/iPhone and the ◊ ratification queue: see [docs/BUILD.md §8](docs/BUILD.md) for the state of the build and verification tiers, [docs/evals/RATIFICATION.md](docs/evals/RATIFICATION.md) for what awaits his decision.

- [ORBIT.md](ORBIT.md) — the product: what Orbit is, its use cases, and the 12-principle constitution
- [docs/DATA-MODEL.md](docs/DATA-MODEL.md) — the schema: bitemporal assertions, events, threads, and why
- [docs/DESIGN.md](docs/DESIGN.md) — the design language: "Two Rooms," tokens, and every ratified surface
- [docs/EVALS.md](docs/EVALS.md) — the evaluation framework: four layers, check IDs, the ratchet; goldens in [docs/evals/goldens/](docs/evals/goldens/)
- [docs/BUILD.md](docs/BUILD.md) — the build plan: stack, module boundaries, milestones and their eval gates, verification tiers; running log in [docs/build/WORKLOG.md](docs/build/WORKLOG.md)
- [docs/prototype/](docs/prototype/) — living HTML mockups; `v3-mockup.html` holds the canonical design tokens
