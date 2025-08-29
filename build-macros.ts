import { execSync } from 'child_process';
import { existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

// Bun macro to get the CR-SQLite extension path at build time
export function getCRSQLiteExtensionPath() {
  // Get directory - works in both Bun (import.meta.dir) and Node.js
  const currentDir = typeof import.meta.dir !== 'undefined' 
    ? import.meta.dir 
    : dirname(fileURLToPath(import.meta.url));
    
  // Check if we already have a bundled extension
  const libDir = resolve(currentDir, 'lib');
  
  // Try platform-specific extension names
  const candidates = [
    resolve(libDir, 'crsqlite.dylib'),       // macOS
    resolve(libDir, 'crsqlite.so'),          // Linux  
  ];
  
  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  
  // If no bundled extension, try to get it from Nix (dev environment)
  try {
    const result = execSync('nix run .#print-path', { 
      encoding: 'utf8',
      cwd: currentDir
    });
    return result.trim();
  } catch (error) {
    throw new Error('CR-SQLite extension not found. Run `bun run bundle-lib` first.');
  }
}