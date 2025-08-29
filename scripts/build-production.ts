#!/usr/bin/env -S npx tsx

import { Console, Effect, pipe, Array as Arr } from "effect";
import { Command, FileSystem, Path } from "@effect/platform";
import { BunContext, BunRuntime } from "@effect/platform-bun";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "..");
const js = String.raw;

interface PlatformTarget {
  readonly nixSystem: string;
  readonly nixTarget: string; // Either .#cr-sqlite or pkgsCross.xxx.cr-sqlite
  readonly platform: string;
  readonly arch: string;
  readonly extension: string;
  readonly description: string;
}

const PLATFORM_TARGETS: ReadonlyArray<PlatformTarget> = [
  {
    nixSystem: "x86_64-linux",
    nixTarget: ".#packages.x86_64-linux.cr-sqlite",
    platform: "linux",
    arch: "x86_64",
    extension: "so",
    description: "Intel/AMD Linux (Docker, most servers)",
  },
  {
    nixSystem: "aarch64-linux",
    nixTarget: ".#packages.aarch64-linux.cr-sqlite",
    platform: "linux",
    arch: "aarch64",
    extension: "so",
    description: "ARM64 Linux (Raspberry Pi 4+, AWS Graviton)",
  },
  {
    nixSystem: "x86_64-darwin",
    nixTarget: ".#packages.x86_64-darwin.cr-sqlite",
    platform: "darwin",
    arch: "x86_64",
    extension: "dylib",
    description: "Intel Mac",
  },
  {
    nixSystem: "aarch64-darwin",
    nixTarget: ".#packages.aarch64-darwin.cr-sqlite",
    platform: "darwin",
    arch: "aarch64",
    extension: "dylib",
    description: "Apple Silicon Mac (M1/M2/M3)",
  },
];

const setupUniversalBuild = Effect.gen(function* () {
  yield* Console.log("⚙️  Setting up universal CR-SQLite build environment...");

  // Enable extra platforms for cross-compilation
  const platforms = PLATFORM_TARGETS.map((t) => t.nixSystem).join(" ");

  yield* Console.log("🌍 Enabling cross-platform builds...");
  yield* Command.make("nix", "build", "--version").pipe(
    Command.exitCode,
    Effect.mapError(() => "Nix not available"),
  );

  // Check if we have remote builders configured
  const hasRemoteBuilders = yield* Command.make("nix", "show-config").pipe(
    Command.string,
    Effect.map((config) => config.includes("builders")),
    Effect.catchAll(() => Effect.succeed(false)),
  );

  if (hasRemoteBuilders) {
    yield* Console.log(
      "🏗️  Remote builders detected - will use for missing platforms",
    );
  } else {
    yield* Console.log(
      "⚡ No remote builders - will try binary cache substitution",
    );
  }
});

const cleanBuildDir = Effect.gen(function* () {
  yield* Console.log("🧹 Cleaning build directory...");
  const fs = yield* FileSystem.FileSystem;

  // Remove existing lib directory
  yield* fs.remove("lib").pipe(Effect.ignore);
  yield* fs.remove("dist").pipe(Effect.ignore);

  // Create fresh directories
  yield* fs.makeDirectory("lib", { recursive: true });
  yield* fs.makeDirectory("dist", { recursive: true });
  yield* fs.makeDirectory("dist/lib", { recursive: true });
});

const buildPlatformExtension = (target: PlatformTarget) =>
  Effect.gen(function* () {
    yield* Console.log(
      `📦 Building ${target.description} (${target.nixSystem})...`,
    );

    // Build using the appropriate nix target
    const buildResult = yield* Command.make(
      "nix",
      "build",
      target.nixTarget,
      "--no-link",
    ).pipe(
      Command.exitCode,
      Effect.mapError(() => `Failed to build ${target.nixTarget}`),
    );

    if (buildResult !== 0) {
      yield* Console.log(
        `❌ Failed to build ${target.nixSystem} - will be missing from package`,
      );
      return null;
    }

    // Get the store path
    const storePath = yield* Command.make(
      "nix",
      "eval",
      target.nixTarget,
      "--raw",
    ).pipe(
      Command.string,
      Effect.mapError(() => `Failed to get store path for ${target.nixTarget}`),
    );

    const fs = yield* FileSystem.FileSystem;

    // Find the actual extension file
    const sourceLibDir = path.join(storePath.trim(), "lib");
    const libFiles = yield* fs.readDirectory(sourceLibDir);

    // Look for the CR-SQLite extension file
    const actualExtFile =
      libFiles.find(
        (file) =>
          file.includes(`crsqlite`) && file.endsWith(`.${target.extension}`),
      );

    if (!actualExtFile) {
      yield* Effect.fail(`No extension file found for ${target.nixSystem}`);
    }

    const sourcePath = path.join(sourceLibDir, actualExtFile!);
    const targetFileName = `crsqlite-${target.platform}-${target.arch}.${target.extension}`;
    const targetPath = path.join("dist", "lib", targetFileName);

    // Copy the extension file (resolving symlinks)
    yield* Command.make("cp", "-L", sourcePath, targetPath).pipe(
      Command.exitCode,
      Effect.mapError(() => `Failed to copy ${sourcePath} to ${targetPath}`),
    );
    yield* Console.log(`✅ ${targetFileName} -> ${target.description}`);

    return {
      target,
      fileName: targetFileName,
      path: targetPath,
    };
  });

const buildAllExtensions = Effect.gen(function* () {
  yield* Console.log("🔨 Building CR-SQLite extensions for ALL platforms...");
  yield* Console.log(
    "🎯 Target: Universal package that Just Works™ everywhere",
  );

  // Build extensions for all platforms - try to get ALL of them
  const results = yield* Effect.all(
    Arr.map(PLATFORM_TARGETS, buildPlatformExtension),
    { concurrency: 2 }, // Build 2 at a time to avoid overwhelming the system
  );

  const successfulBuilds = results.filter(Boolean);
  const failedBuilds = PLATFORM_TARGETS.length - successfulBuilds.length;

  if (failedBuilds > 0) {
    yield* Console.log(
      `⚠️  Missing ${failedBuilds} platforms - package won't be truly universal`,
    );
    yield* Console.log(
      `💡 Consider setting up Nix remote builders for missing platforms`,
    );

    // List what's missing
    const builtPlatforms = successfulBuilds.map((b) => b.target.nixSystem);
    const missingPlatforms = PLATFORM_TARGETS.filter(
      (t) => !builtPlatforms.includes(t.nixSystem),
    ).map((t) => `${t.nixSystem} (${t.description})`);

    yield* Console.log(`❌ Missing: ${missingPlatforms.join(", ")}`);
  } else {
    yield* Console.log(
      `🎉 SUCCESS: Built ALL ${PLATFORM_TARGETS.length} platforms - truly universal!`,
    );
  }

  yield* Console.log(
    `✨ Built ${successfulBuilds.length}/${PLATFORM_TARGETS.length} platform extensions`,
  );

  return successfulBuilds;
});

const generateOptimizedIndex = (builtExtensions: Array<any>) =>
  Effect.gen(function* () {
    yield* Console.log("📝 Generating optimized index.js for production...");

    const fs = yield* FileSystem.FileSystem;

    const indexContent = `import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Get the absolute path to the bundled CR-SQLite extension
 * Automatically detects platform and architecture
 * @returns {string} Absolute path to crsqlite.dylib/.so
 */
export function getExtensionPath() {
  // Browser check - prevent misuse in browsers
  if (typeof window !== 'undefined') {
    throw new Error(
      '@effect-native/libcrsql is for Node.js server environments only. ' +
      'For browsers, use sql.js or a server-side database API.'
    );
  }

  // Detect current platform and architecture
  const platform = process.platform === 'darwin' ? 'darwin' : 'linux';
  const arch = process.arch === 'arm64' ? 'aarch64' : 'x86_64';
  const ext = platform === 'darwin' ? 'dylib' : 'so';

  const libDir = resolve(__dirname, 'lib');

  // Try platform-specific extension first (highest priority)
  const specificExt = resolve(libDir, \`crsqlite-\${platform}-\${arch}.\${ext}\`);
  if (existsSync(specificExt)) {
    return specificExt;
  }

  // Fallback to any available extension for the current platform
  const fallbackCandidates = [
    resolve(libDir, \`crsqlite.\${ext}\`),        // Generic for platform
    resolve(libDir, 'crsqlite.dylib'),         // macOS generic
    resolve(libDir, 'crsqlite.so'),            // Linux generic
  ];

  for (const candidate of fallbackCandidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  // Helpful error message with available platforms
  const availablePlatforms = ${JSON.stringify(builtExtensions.map((b) => `${b.target.platform}-${b.target.arch}`))};
  const expectedExt = \`crsqlite-\${platform}-\${arch}.\${ext}\`;
  throw new Error(
    \`CR-SQLite extension not found for \${platform}/\${arch}. \` +
    \`Expected: \${expectedExt}. \` +
    \`Available platforms: \${availablePlatforms.join(', ')}. \` +
    \`This package supports: ${PLATFORM_TARGETS.map((t) => t.description).join(", ")}\`
  );
}

/**
 * Path to CR-SQLite extension - for use with db.loadExtension()
 * Automatically detects your platform and returns the right extension
 */
export const pathToCRSQLiteExtension = getExtensionPath();

/**
 * Default export - same as pathToCRSQLiteExtension
 */
export default pathToCRSQLiteExtension;
`;

    yield* fs.writeFileString("dist/index.js", indexContent);

    // Generate TypeScript definitions
    const dtsContent = js`/**
 * Get the absolute path to the bundled CR-SQLite extension
 * @returns Absolute path to crsqlite.dylib/.so
 */
export declare function getExtensionPath(): string;

/**
 * Path to CR-SQLite extension - for use with db.loadExtension()
 */
export declare const pathToCRSQLiteExtension: string;

/**
 * Default export - same as pathToCRSQLiteExtension
 */
declare const _default: string;
export default _default;
`;

    yield* fs.writeFileString("dist/index.d.ts", dtsContent);

    // Generate React Native specific entry point
    const reactNativeContent = js`// React Native specific entry point
// CR-SQLite extensions don't work in React Native

/**
 * React Native placeholder for getExtensionPath
 * @throws Always throws with helpful message for React Native users
 */
export function getExtensionPath() {
  throw new Error(
    '🚫 @effect-native/libcrsql is for Node.js / Bun server environments only.\n\n' +
    '📱 For React Native, use one of these instead:\n' +
    '  • @op-engineering/op-sqlite: https://www.npmjs.com/package/@op-engineering/op-sqlite\n' +
    '  • expo-sqlite: https://docs.expo.dev/versions/latest/sdk/sqlite/\n' +
    '💡 This package provides native CR-SQLite extensions for Node.js / Bun servers, not mobile apps.'
  );
}

/**
 * React Native placeholder for pathToCRSQLiteExtension
 * @throws Always throws with helpful message
 */
export const pathToCRSQLiteExtension = (() => {
  throw new Error(
    '🚫 @effect-native/libcrsql is for Node.js / Bun server environments only.\n\n' +
    '📱 For React Native, use one of these instead:\n' +
    '  • @op-engineering/op-sqlite: https://www.npmjs.com/package/@op-engineering/op-sqlite\n' +
    '  • expo-sqlite: https://docs.expo.dev/versions/latest/sdk/sqlite/\n' +
    '💡 This package provides native CR-SQLite extensions for Node.js / Bun servers, not mobile apps.'
  );
})();

export default pathToCRSQLiteExtension;
`;

    yield* fs.writeFileString("dist/react-native.js", reactNativeContent);

    // TypeScript definitions for React Native
    const reactNativeDtsContent = js`/**
 * React Native placeholder for getExtensionPath
 * @throws Always throws with helpful message for React Native users
 */
export declare function getExtensionPath(): never;

/**
 * React Native placeholder for pathToCRSQLiteExtension
 * @throws Always throws with helpful message for React Native users
 */
export declare const pathToCRSQLiteExtension: never;

export default pathToCRSQLiteExtension;
`;

    yield* fs.writeFileString("dist/react-native.d.ts", reactNativeDtsContent);
  });

const generateOptimizedBin = Effect.gen(function* () {
  yield* Console.log("🔧 Generating optimized bin script...");

  const fs = yield* FileSystem.FileSystem;
  yield* fs.makeDirectory("dist/bin", { recursive: true });

  const binContent = js`#!/usr/bin/env node

import { pathToCRSQLiteExtension } from '../index.js';

try {
  console.log(pathToCRSQLiteExtension);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
`;

  yield* fs.writeFileString("dist/bin/libcrsql-extension-path.js", binContent);

  // Make it executable
  yield* Command.make("chmod", "+x", "dist/bin/libcrsql-extension-path.js").pipe(
    Command.exitCode,
  );
});

const generateProductionPackageJson = Effect.gen(function* () {
  yield* Console.log("📦 Generating production package.json...");

  const fs = yield* FileSystem.FileSystem;

  // Read current package.json
  const currentPackageJson = yield* fs.readFileString("package.json");
  const pkg = JSON.parse(currentPackageJson);

  // Create production version
  const prodPkg = {
    ...pkg,
    main: "index.js",
    types: "index.d.ts",
    exports: {
      ".": {
        "react-native": "./react-native.js",
        default: "./index.js",
      },
      "./react-native": {
        import: "./react-native.js",
        types: "./react-native.d.ts",
      },
      "./package.json": "./package.json",
    },
    bin: {
      "@effect-native/libcrsql": "./bin/libcrsql-extension-path.js",
      "libcrsql-extension-path": "./bin/libcrsql-extension-path.js",
    },
    files: [
      "index.js",
      "index.d.ts",
      "react-native.js",
      "react-native.d.ts",
      "lib/",
      "bin/",
      "README.md",
    ],
  };

  yield* fs.writeFileString(
    "dist/package.json",
    JSON.stringify(prodPkg, null, 2),
  );
});

const copyStaticFiles = Effect.gen(function* () {
  yield* Console.log("📋 Copying static files...");

  const fs = yield* FileSystem.FileSystem;

  // Copy README and other essential files - create a basic README if it doesn't exist
  const readmeExists = yield* fs.exists("README.md");
  if (readmeExists) {
    yield* fs.copy("README.md", "dist/README.md");
  } else {
    const basicReadme = `# @effect-native/libcrsql

Pure-Nix CR-SQLite extension for conflict-free replicated databases.

## Installation

\`\`\`bash
npm install @effect-native/libcrsql
\`\`\`

## Usage

\`\`\`javascript
import { pathToCRSQLiteExtension } from '@effect-native/libcrsql';
import sqlite3 from 'sqlite3';

const db = new sqlite3.Database(':memory:');
db.loadExtension(pathToCRSQLiteExtension);

// Now you can use CR-SQLite functions
db.run("SELECT crsql_as_crr('users')");
\`\`\`

## CLI

\`\`\`bash
# Get path to extension
npx libcrsql-extension-path
\`\`\`
`;
    yield* fs.writeFileString("dist/README.md", basicReadme);
  }
});

const generateBuildSummary = (builtExtensions: Array<any>) =>
  Effect.gen(function* () {
    yield* Console.log("\n🎉 Production build complete!");
    yield* Console.log("📊 Build Summary:");
    yield* Console.log(`   Built extensions: ${builtExtensions.length}`);

    for (const ext of builtExtensions) {
      yield* Console.log(`   ✅ ${ext.fileName} - ${ext.target.description}`);
    }

    yield* Console.log("\n📦 Production package created in ./dist/");
    yield* Console.log("🚀 Ready for: cd dist && npm publish");

    const fs = yield* FileSystem.FileSystem;
    const distFiles = yield* fs.readDirectory("dist");
    yield* Console.log(`📁 Package contents: ${distFiles.join(", ")}`);
  });

const main = Effect.gen(function* () {
  yield* Console.log(
    "🚀 Building UNIVERSAL production package for @effect-native/libcrsql",
  );
  yield* Console.log(
    "🎯 Goal: Just Works™ everywhere - Mac, Linux, Pi, Docker, Vercel, etc.",
  );

  yield* setupUniversalBuild;
  yield* cleanBuildDir;
  const builtExtensions = yield* buildAllExtensions;

  if (builtExtensions.length < PLATFORM_TARGETS.length) {
    yield* Console.log(
      "⚠️  WARNING: Not all platforms built - package won't be truly universal",
    );
  }

  yield* generateOptimizedIndex(builtExtensions);
  yield* generateOptimizedBin;
  yield* generateProductionPackageJson;
  yield* copyStaticFiles;
  yield* generateBuildSummary(builtExtensions);

  if (builtExtensions.length === PLATFORM_TARGETS.length) {
    yield* Console.log("🎉 SUCCESS: Created truly UNIVERSAL package!");
    yield* Console.log(
      "✅ Works on Mac, Linux, Pi, Docker, Vercel - everywhere!",
    );
  }
});

// Run when called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const program = main.pipe(
    Effect.provide(BunContext.layer),
    Effect.catchAll((error) => Console.error(`Build failed: ${error}`)),
  );
  BunRuntime.runMain(program);
}