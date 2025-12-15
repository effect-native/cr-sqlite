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

Tracking:
- Submodules + TS-work rule: [`.tasks/backlog/TASK-038-add-effect-native-submodules.md`](../.tasks/backlog/TASK-038-add-effect-native-submodules.md)
- Global mesh package-map spec (Phase 1): [`.tasks/backlog/TASK-039-spec-global-mesh-package-map.md`](../.tasks/backlog/TASK-039-spec-global-mesh-package-map.md)
- Protocol spec: [`.tasks/backlog/TASK-040-spec-crsql-mesh-protocol.md`](../.tasks/backlog/TASK-040-spec-crsql-mesh-protocol.md)
- Core engine spec: [`.tasks/backlog/TASK-041-spec-crsql-mesh-core.md`](../.tasks/backlog/TASK-041-spec-crsql-mesh-core.md)
- Transport interface spec: [`.tasks/backlog/TASK-042-spec-crsql-mesh-transport.md`](../.tasks/backlog/TASK-042-spec-crsql-mesh-transport.md)
- `@effect-native/crsql` integration spec: [`.tasks/backlog/TASK-043-spec-crsql-mesh-integration.md`](../.tasks/backlog/TASK-043-spec-crsql-mesh-integration.md)
- `@effect-native/libcrsql` changes spec: [`.tasks/backlog/TASK-044-spec-libcrsql-next.md`](../.tasks/backlog/TASK-044-spec-libcrsql-next.md)
- Runtime adapters spec: [`.tasks/backlog/TASK-045-spec-crsql-mesh-runtime.md`](../.tasks/backlog/TASK-045-spec-crsql-mesh-runtime.md)
