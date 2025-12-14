# Rails Solid Queue: Source Notes

Repo: `.refs/solid_queue`

## Summary
Solid Queue is a database-backed Active Job adapter built around a durable **job row** plus a set of **execution state tables** (ready/scheduled/claimed/failed/blocked). Work is coordinated via SQL transactions and (where supported) `FOR UPDATE SKIP LOCKED`.

Key actors:
- **Worker**: claims ready jobs and executes them.
- **Dispatcher**: moves scheduled jobs into ready, and runs concurrency maintenance.
- **Scheduler**: enqueues recurring tasks with dedupe.
- **Supervisor**: runs and monitors processes, prunes dead ones, fails orphaned claims.

The core property it tries to provide is “run a job once” in the presence of process crashes, by using claimed rows + heartbeats + orphan recovery.

## Key Modules / Files
- ActiveJob adapter: `.refs/solid_queue/lib/active_job/queue_adapters/solid_queue_adapter.rb`
- Supervisor: `.refs/solid_queue/lib/solid_queue/supervisor.rb`
- Worker: `.refs/solid_queue/lib/solid_queue/worker.rb`
- Dispatcher: `.refs/solid_queue/lib/solid_queue/dispatcher.rb`
- Scheduler: `.refs/solid_queue/lib/solid_queue/scheduler.rb`
- Models + state machine: `.refs/solid_queue/app/models/solid_queue/*`
- Canonical schema template: `.refs/solid_queue/lib/generators/solid_queue/install/templates/db/queue_schema.rb`

## Schema (Conceptual)
- `solid_queue_jobs`: job payload, scheduling metadata.
- `solid_queue_ready_executions`: claimable jobs.
- `solid_queue_scheduled_executions`: future jobs.
- `solid_queue_claimed_executions`: in-flight jobs with `process_id`.
- `solid_queue_failed_executions`: failed jobs + error JSON.
- `solid_queue_blocked_executions`: jobs waiting for concurrency token.
- `solid_queue_semaphores`: global concurrency tokens per `concurrency_key`.
- `solid_queue_processes`: registrations + heartbeats.
- `solid_queue_pauses`: paused queue names.
- `solid_queue_recurring_tasks` + `solid_queue_recurring_executions`: recurring schedules + run dedupe.

## Coordination Algorithm Notes
- Claiming and dispatching are explicit **table moves** (insert claim/ready row + delete from prior state table).
- Concurrency controls implemented via `semaphores` + `blocked_executions` and a “release-one” promotion path.
- Heartbeats enable pruning and orphan recovery.

## SQLite / cr-sqlite Suitability
### Plain SQLite
Solid Queue acknowledges SQLite limitations: without row-level `SKIP LOCKED`, contention is higher; writes are serialized. Still workable with WAL + short transactions.

### cr-sqlite
Using cr-sqlite replication *directly* for the whole queue is risky:
- Queue execution is a side effect; if “ready/claimed” state is replicated, multiple replicas can run the same job.
- Global semaphores are not a CRDT without redesign.

A cr-sqlite-backed design must separate:
- **Replicated intent** (job definitions / schedules)
- **Local execution coordination** (claims, in-flight, heartbeats, semaphores)

If we want multi-writer replicated queues, we need a new semantics layer (“lease CRDT” or deterministic leader/provider model).
