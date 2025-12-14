we need to start thinking about the ideal release plans
where/how shall we release the zig stuff?
how shall we explain what it is, how to get it, and how to use it?
etc

don't do it yet, just write up a proposal for what needs to exist for the ideal release across wherever people get native stuff these days
figure out where people get native stuff
e.g. nix, npm, ???

---

## Completed: 2025-12-14

**Proposal:** `research/zig-cr/103-release-planning-proposal.md`

**Summary:**
- Primary channel: npm with platform-specific optional dependency packages
- Secondary: GitHub Releases for raw binaries, Nix flakes for reproducible builds
- Staged rollout: Browser beta (week 1) → Linux (week 2) → macOS/Windows (week 3) → Stable (week 4)
- Versioning: Aligned versions across all packages (0.17.0)
- Docs: In-repo, near code (README.md updates, browser-dist/README.md)

**Next engineering tasks identified:**
- TASK-037: Publish browser package to npm beta
- TASK-038: Set up Zig Linux CI builds
- TASK-039: Create platform-specific npm packages
