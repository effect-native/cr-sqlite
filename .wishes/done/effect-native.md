add reference submodules
- git@github.com:Effect-TS/effect.git
- git@github.com:Effect-TS/effect-smol.git

add work submodule
- git@github.com:effect-native/effect-native.git

add this rule to our AGENTS.md rules:

all typescript work shall be done in our effect-native submodule
we follow the spec-first workflow defined in effect-native/.specs/AGENTS.md

let's start planning a set of new packages for all this stuff
especially research/zig-cr/102-proposal-crsqlite-global-mesh.md

---

## Completed: 2025-12-15

- Reference submodules added: `.refs/effect/`, `.refs/effect-smol/`
- Work submodule added: `effect-native/`
- Repo rule added: all TS work lives in `effect-native/` and follows `effect-native/.specs/AGENTS.md`
- Global mesh planning/specs created under `effect-native/.specs/`

Tracking (historical):
- Submodules + TS-work rule: [`.tasks/done/TASK-038-add-effect-native-submodules.md`](../../.tasks/done/TASK-038-add-effect-native-submodules.md)
- Global mesh package-map spec (Phase 1): [`.tasks/done/TASK-039-spec-global-mesh-package-map.md`](../../.tasks/done/TASK-039-spec-global-mesh-package-map.md)
- Protocol spec: [`.tasks/done/TASK-040-spec-crsql-mesh-protocol.md`](../../.tasks/done/TASK-040-spec-crsql-mesh-protocol.md)
- Core engine spec: [`.tasks/done/TASK-041-spec-crsql-mesh-core.md`](../../.tasks/done/TASK-041-spec-crsql-mesh-core.md)
- Transport interface spec: [`.tasks/done/TASK-042-spec-crsql-mesh-transport.md`](../../.tasks/done/TASK-042-spec-crsql-mesh-transport.md)
- `@effect-native/crsql` integration spec: [`.tasks/done/TASK-043-spec-crsql-mesh-integration.md`](../../.tasks/done/TASK-043-spec-crsql-mesh-integration.md)
- `@effect-native/libcrsql` changes spec: [`.tasks/done/TASK-044-spec-libcrsql-next.md`](../../.tasks/done/TASK-044-spec-libcrsql-next.md)
- Runtime adapters spec: [`.tasks/done/TASK-045-spec-crsql-mesh-runtime.md`](../../.tasks/done/TASK-045-spec-crsql-mesh-runtime.md)
- Phase 2 requirements (node-first slice): [`.tasks/done/TASK-046-phase2-requirements-crsql-mesh.md`](../../.tasks/done/TASK-046-phase2-requirements-crsql-mesh.md)
