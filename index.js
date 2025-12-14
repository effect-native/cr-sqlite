import { getCRSQLiteExtensionPath } from './build-macros.ts' with { type: 'macro' };
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Get the extension path at build time using macro
const CRSQLITE_EXTENSION_PATH = getCRSQLiteExtensionPath();

/**
 * Extension implementation type - Zig is the new pure-Zig rewrite, 
 * C/Rust is the original upstream implementation
 * @type {'zig' | 'c-rust' | 'auto'}
 */
export const PREFER_IMPLEMENTATION = process.env.CRSQLITE_IMPL || 'auto';

/**
 * Get the absolute path to the bundled CR-SQLite extension
 * @param {Object} options - Configuration options
 * @param {('zig'|'c-rust'|'auto')} [options.implementation='auto'] - Which implementation to prefer
 * @returns {string} Absolute path to crsqlite.dylib/.so
 */
export function getExtensionPath(options = {}) {
  const impl = options.implementation || PREFER_IMPLEMENTATION;
  
  // Detect platform and architecture
  const platform = process.platform === 'darwin' ? 'darwin' : 'linux';
  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const ext = platform === 'darwin' ? 'dylib' : 'so';
  
  const libDir = resolve(__dirname, 'lib');
  
  // Build candidates list based on implementation preference
  const zigSpecific = resolve(libDir, `crsqlite-zig-${platform}-${arch}.${ext}`);
  const cRustSpecific = resolve(libDir, `crsqlite-${platform}-${arch}.${ext}`);
  
  // Priority order depends on implementation preference
  let candidates = [];
  
  if (impl === 'zig') {
    // Zig-only: only try Zig artifacts
    candidates = [zigSpecific];
  } else if (impl === 'c-rust') {
    // C/Rust-only: only try C/Rust artifacts
    candidates = [cRustSpecific];
  } else {
    // Auto mode: prefer Zig (new), fall back to C/Rust (legacy)
    candidates = [zigSpecific, cRustSpecific];
  }
  
  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  
  // If we have a build-time path and it exists, use it as fallback
  if (CRSQLITE_EXTENSION_PATH && existsSync(CRSQLITE_EXTENSION_PATH)) {
    return CRSQLITE_EXTENSION_PATH;
  }
  
  // Fallback to generic extensions (for development/backwards compatibility)
  const fallbackCandidates = [
    resolve(libDir, `crsqlite.${ext}`),        // Generic for platform
    resolve(libDir, 'crsqlite.dylib'),         // macOS generic
    resolve(libDir, 'crsqlite.so'),            // Linux generic
  ];
  
  for (const candidate of fallbackCandidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  
  // Helpful error message
  const zigExt = `crsqlite-zig-${platform}-${arch}.${ext}`;
  const cRustExt = `crsqlite-${platform}-${arch}.${ext}`;
  throw new Error(
    `CR-SQLite extension not found for ${platform}/${arch}. ` +
    `Expected: ${impl === 'zig' ? zigExt : impl === 'c-rust' ? cRustExt : `${zigExt} or ${cRustExt}`}. ` +
    `Run 'npm run bundle-lib' to build platform-specific extensions.`
  );
}

/**
 * Hip alias for getExtensionPath() - for use with db.loadExtension()
 * @returns {string} Absolute path to crsqlite.dylib/.so
 */
export const pathToCRSQLiteExtension = getExtensionPath();

export default getExtensionPath;