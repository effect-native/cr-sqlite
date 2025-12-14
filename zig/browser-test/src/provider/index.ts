/**
 * Provider Module
 *
 * Re-exports provider worker for use by tabs elected as database owner.
 */

// The worker is loaded directly as a module worker, not imported here.
// This file serves as the module entry point for the provider package.

export type { RpcRequest, RpcResponse } from '../shared/rpc-types';
