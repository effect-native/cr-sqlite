import { getCRSQLiteExtensionPath } from './build-macros.ts' with { type: 'macro' };
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Get the extension path at build time using macro
const CRSQLITE_EXTENSION_PATH = getCRSQLiteExtensionPath();

/**
 * Get the absolute path to the bundled CR-SQLite extension
 * @returns {string} Absolute path to crsqlite.dylib/.so
 */
export function getExtensionPath() {
  // Detect platform and architecture
  const platform = process.platform === 'darwin' ? 'darwin' : 'linux';
  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const ext = platform === 'darwin' ? 'dylib' : 'so';
  
  const libDir = resolve(__dirname, 'lib');
  
  // Try platform-specific extension first (highest priority)
  const specificExt = resolve(libDir, `crsqlite-${platform}-${arch}.${ext}`);
  if (existsSync(specificExt)) {
    return specificExt;
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
  const expectedExt = `crsqlite-${platform}-${arch}.${ext}`;
  throw new Error(
    `CR-SQLite extension not found for ${platform}/${arch}. ` +
    `Expected: ${expectedExt}. ` +
    `Run 'npm run bundle-lib' to build platform-specific extensions.`
  );
}

/**
 * Hip alias for getExtensionPath() - for use with db.loadExtension()
 * @returns {string} Absolute path to crsqlite.dylib/.so
 */
export const pathToCRSQLiteExtension = getExtensionPath();

export default getExtensionPath;