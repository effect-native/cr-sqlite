#!/usr/bin/env node
/*
  Minimal production packager without tsx (works in sandboxed CI):
  - Copies prebuilt libs from ./lib into ./dist/lib
  - Emits dist/index.js with runtime platform detection
  - Emits types, RN stubs, bin script, and a production package.json
  - Copies README.md
*/
const fs = require('fs');
const path = require('path');

function rimraf(p) {
  if (!fs.existsSync(p)) return;
  for (const entry of fs.readdirSync(p)) {
    const full = path.join(p, entry);
    const st = fs.lstatSync(full);
    if (st.isDirectory() && !st.isSymbolicLink()) rimraf(full);
    else fs.rmSync(full, { force: true });
  }
  fs.rmdirSync(p, { recursive: true });
}

function mkdirp(p) {
  fs.mkdirSync(p, { recursive: true });
}

function copyFile(src, dst) {
  mkdirp(path.dirname(dst));
  fs.copyFileSync(src, dst);
}

function copyDir(src, dst) {
  if (!fs.existsSync(src)) return;
  for (const entry of fs.readdirSync(src)) {
    const s = path.join(src, entry);
    const d = path.join(dst, entry);
    const st = fs.lstatSync(s);
    if (st.isDirectory() && !st.isSymbolicLink()) copyDir(s, d);
    else copyFile(s, d);
  }
}

console.log('🧹 Cleaning dist/ ...');
rimraf('dist');
mkdirp('dist/lib');
mkdirp('dist/bin');

console.log('📦 Copying prebuilt libs from ./lib -> ./dist/lib');
copyDir('lib', 'dist/lib');

console.log('📝 Writing dist/index.js / index.d.ts');
const indexJs = `import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

export function getExtensionPath() {
  if (typeof window !== 'undefined') {
    throw new Error(
      '@effect-native/libcrsql is for Node.js / Bun server environments only.'
    );
  }
  const platform = process.platform === 'darwin' ? 'darwin' : 'linux';
  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const ext = platform === 'darwin' ? 'dylib' : 'so';
  const libDir = resolve(__dirname, 'lib');

  const specific = resolve(libDir, \
    \`crsqlite-\${platform}-\${arch}.\${ext}\`);
  if (existsSync(specific)) return specific;

  const fallbacks = [
    resolve(libDir, \`crsqlite.\${ext}\`),
    resolve(libDir, 'crsqlite.dylib'),
    resolve(libDir, 'crsqlite.so'),
  ];
  for (const c of fallbacks) if (existsSync(c)) return c;

  throw new Error(
    \`CR-SQLite extension not found for \${platform}/\${arch}. ` +
    `Run \"npm run bundle-lib\" first or use the prebuilt package.\`
  );
}

export const pathToCRSQLiteExtension = getExtensionPath();
export default pathToCRSQLiteExtension;
`;
fs.writeFileSync('dist/index.js', indexJs);

const indexDts = `/** Get the absolute path to the bundled CR-SQLite extension */
export declare function getExtensionPath(): string;
export declare const pathToCRSQLiteExtension: string;
export default pathToCRSQLiteExtension;
`;
fs.writeFileSync('dist/index.d.ts', indexDts);

console.log('📝 Writing dist/react-native stubs');
const rnJs = `export function getExtensionPath() {
  throw new Error(
    '🚫 @effect-native/libcrsql is for Node.js / Bun server environments only.\n\n' +
    '📱 For React Native, use: @op-engineering/op-sqlite or expo-sqlite.'
  );
}
export const pathToCRSQLiteExtension = (() => { getExtensionPath(); })();
export default pathToCRSQLiteExtension;
`;
const rnDts = `export declare function getExtensionPath(): never;
export declare const pathToCRSQLiteExtension: never;
export default pathToCRSQLiteExtension;
`;
fs.writeFileSync('dist/react-native.js', rnJs);
fs.writeFileSync('dist/react-native.d.ts', rnDts);

console.log('🔧 Writing dist/bin/libcrsql-extension-path.js');
const binJs = `#!/usr/bin/env node
import { pathToCRSQLiteExtension } from '../index.js';
console.log(pathToCRSQLiteExtension);
`;
fs.writeFileSync('dist/bin/libcrsql-extension-path.js', binJs);
fs.chmodSync('dist/bin/libcrsql-extension-path.js', 0o755);

console.log('📦 Writing dist/package.json');
const rootPkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const prodPkg = {
  name: rootPkg.name,
  version: rootPkg.version,
  description: rootPkg.description,
  type: 'module',
  main: './index.js',
  types: './index.d.ts',
  exports: {
    '.': {
      'react-native': './react-native.js',
      default: './index.js'
    },
    './react-native': { import: './react-native.js', types: './react-native.d.ts' },
    './package.json': './package.json'
  },
  bin: {
    '@effect-native/libcrsql': './bin/libcrsql-extension-path.js',
    'libcrsql-extension-path': './bin/libcrsql-extension-path.js'
  },
  files: [
    'index.js', 'index.d.ts',
    'react-native.js', 'react-native.d.ts',
    'lib/', 'bin/', 'README.md'
  ],
  license: rootPkg.license,
  repository: rootPkg.repository,
  keywords: rootPkg.keywords,
  publishConfig: rootPkg.publishConfig
};
fs.writeFileSync('dist/package.json', JSON.stringify(prodPkg, null, 2));

console.log('📋 Copying README.md');
if (fs.existsSync('README.md')) copyFile('README.md', 'dist/README.md');

console.log('✅ Production package created in ./dist');
console.log('   -> Ready: cd dist && npm publish');

