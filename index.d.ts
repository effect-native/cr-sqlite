/**
 * Extension implementation type - Zig is the new pure-Zig rewrite,
 * C/Rust is the original upstream implementation
 */
export type Implementation = 'zig' | 'c-rust' | 'auto';

/**
 * Options for getExtensionPath
 */
export interface GetExtensionPathOptions {
  /**
   * Which implementation to prefer:
   * - 'zig': Only use Zig-built artifacts
   * - 'c-rust': Only use C/Rust-built artifacts (legacy)
   * - 'auto': Prefer Zig, fall back to C/Rust (default)
   */
  implementation?: Implementation;
}

/**
 * The preferred implementation, controlled by CRSQLITE_IMPL env var.
 * Defaults to 'auto' which prefers Zig artifacts.
 */
export declare const PREFER_IMPLEMENTATION: Implementation;

/**
 * Get the absolute path to the bundled CR-SQLite extension
 * @param options - Configuration options
 * @returns Absolute path to crsqlite.dylib/.so
 */
export declare function getExtensionPath(options?: GetExtensionPathOptions): string;

/**
 * Path to CR-SQLite extension - for use with db.loadExtension()
 * Uses the default implementation preference (PREFER_IMPLEMENTATION)
 */
export declare const pathToCRSQLiteExtension: string;

/**
 * Default export - same as getExtensionPath
 */
declare const _default: (options?: GetExtensionPathOptions) => string;
export default _default;
