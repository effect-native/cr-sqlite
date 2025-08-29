#!/usr/bin/env -S npx tsx

import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function getExtensionPath() {
  // Detect platform and architecture
  const platform = process.platform === 'darwin' ? 'darwin' : 'linux';
  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const ext = platform === 'darwin' ? 'dylib' : 'so';
  
  const libDir = resolve(__dirname, '..', 'lib');
  
  // Try platform-specific extension first
  const specificExt = resolve(libDir, `crsqlite-${platform}-${arch}.${ext}`);
  if (existsSync(specificExt)) {
    return specificExt;
  }
  
  // Fallback to generic extensions
  const fallbackCandidates = [
    resolve(libDir, `crsqlite.${ext}`),
    resolve(libDir, 'crsqlite.dylib'),
    resolve(libDir, 'crsqlite.so'),
  ];
  
  for (const candidate of fallbackCandidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  
  throw new Error(`CR-SQLite extension not found for ${platform}/${arch}`);
}

// Run when called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    console.log(getExtensionPath())
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}