/**
 * Coordinator Module
 *
 * Re-exports SharedWorker coordinator functionality for multi-tab database access.
 */

// The SharedWorker runs in its own context, so we just re-export the path
// and any utilities that might be useful for the main thread.

export { SHARED_WORKER_PATH } from '../shared/constants';

// Note: The actual SharedWorker code (shared-worker.ts) runs in a separate
// worker context and cannot be directly imported into the main thread.
// Use SHARED_WORKER_PATH to instantiate: new SharedWorker(SHARED_WORKER_PATH)
