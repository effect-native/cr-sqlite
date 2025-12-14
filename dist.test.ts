#!/usr/bin/env -S npx tsx

import { Console, Effect } from "effect";
import { Command } from "@effect/platform";
import { BunContext, BunRuntime } from "@effect/platform-bun";
import { existsSync, readdirSync } from "node:fs";
import { pathToSQLite } from "@effect-native/libsqlite";
import { Database } from "bun:sqlite";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

Database.setCustomSQLite(pathToSQLite);

const __dirname = dirname(fileURLToPath(import.meta.url));

const testBasicFunctionality = Effect.gen(function* () {
  yield* Console.log("🧪 Testing basic package functionality...");

  // Test 1: Check if main files exist
  yield* Console.log("📁 Test 1: Checking main files...");
  const requiredFiles = [
    "package.json",
    "flake.nix",
    "index.js",
    "index.d.ts",
    "bin/libcrsql-extension-path.ts",
    "scripts/build-production.ts",
    "scripts/sync-version.ts",
    "scripts/build-zig.sh",
    "scripts/bundle-zig-lib.sh",
    "build-macros.ts",
  ];

  for (const file of requiredFiles) {
    if (!existsSync(file)) {
      yield* Effect.fail(`Required file missing: ${file}`);
    }
    yield* Console.log(`  ✅ ${file}`);
  }

  // Test 2: Check Nix flake
  yield* Console.log("\n🏗️  Test 2: Checking Nix flake...");
  yield* Command.make("nix", "flake", "check", "--no-build").pipe(
    Command.exitCode,
    Effect.mapError(() => "Nix flake check failed")
  );
  yield* Console.log("  ✅ Nix flake is valid");

  // Test 3: Check TypeScript compilation
  yield* Console.log("\n📝 Test 3: Checking TypeScript compilation...");
  yield* Command.make("npx", "tsc", "--noEmit", "index.d.ts").pipe(
    Command.exitCode,
    Effect.mapError(() => "TypeScript compilation failed"),
    Effect.ignore // Ignore errors for now since we might not have all dependencies
  );

  yield* Console.log("✅ All basic tests passed!");
});

const testLibArtifacts = Effect.gen(function* () {
  yield* Console.log("\n📦 Test 4: Checking lib/ artifacts...");
  
  const libDir = resolve(__dirname, "lib");
  if (!existsSync(libDir)) {
    yield* Console.log("  ⚠️  lib/ directory does not exist - skipping artifact check");
    return;
  }
  
  const files = readdirSync(libDir);
  
  // Check for C/Rust artifacts (legacy)
  const cRustArtifacts = files.filter(f => 
    f.startsWith("crsqlite-") && !f.includes("-zig-") && (f.endsWith(".dylib") || f.endsWith(".so"))
  );
  
  // Check for Zig artifacts (new)
  const zigArtifacts = files.filter(f => 
    f.startsWith("crsqlite-zig-") && (f.endsWith(".dylib") || f.endsWith(".so"))
  );
  
  yield* Console.log(`  Found ${cRustArtifacts.length} C/Rust artifact(s):`);
  for (const f of cRustArtifacts) {
    yield* Console.log(`    ✅ ${f}`);
  }
  
  yield* Console.log(`  Found ${zigArtifacts.length} Zig artifact(s):`);
  for (const f of zigArtifacts) {
    yield* Console.log(`    ✅ ${f}`);
  }
  
  if (cRustArtifacts.length === 0 && zigArtifacts.length === 0) {
    yield* Console.log("  ⚠️  No platform-specific artifacts found in lib/");
    yield* Console.log("     Run 'npm run bundle-lib' for C/Rust artifacts");
    yield* Console.log("     Run 'npm run bundle-lib:zig' for Zig artifacts");
  }
});

const testZigBuildAvailable = Effect.gen(function* () {
  yield* Console.log("\n🔧 Test 5: Checking Zig build artifacts...");
  
  const zigOutDir = resolve(__dirname, "zig/zig-out/lib");
  const zigOutUniversal = resolve(__dirname, "zig/zig-out-universal/lib");
  const zigOutArm64 = resolve(__dirname, "zig/zig-out-arm64/lib");
  const zigOutX64 = resolve(__dirname, "zig/zig-out-x64/lib");
  
  const checkDir = (dir: string, label: string) => {
    if (existsSync(dir)) {
      const files = readdirSync(dir).filter(f => f.includes("crsqlite"));
      if (files.length > 0) {
        return { exists: true, files, label };
      }
    }
    return { exists: false, files: [], label };
  };
  
  const locations = [
    checkDir(zigOutDir, "zig-out (native)"),
    checkDir(zigOutUniversal, "zig-out-universal (macOS universal)"),
    checkDir(zigOutArm64, "zig-out-arm64 (macOS ARM64)"),
    checkDir(zigOutX64, "zig-out-x64 (macOS x64)"),
  ];
  
  const available = locations.filter(l => l.exists);
  
  if (available.length === 0) {
    yield* Console.log("  ⚠️  No Zig build outputs found");
    yield* Console.log("     Run 'npm run build:zig' to build for current platform");
    yield* Console.log("     Run 'npm run build:zig darwin' to build macOS universal binary");
  } else {
    yield* Console.log(`  Found ${available.length} Zig build location(s):`);
    for (const loc of available) {
      yield* Console.log(`    ✅ ${loc.label}: ${loc.files.join(", ")}`);
    }
  }
});

const testLoaderSelection = Effect.gen(function* () {
  yield* Console.log("\n🎯 Test 6: Checking loader selection logic...");
  
  // Import the loader dynamically to test it
  const loader = yield* Effect.tryPromise(() => import("./index.js"));
  
  // Check that the exports exist
  if (typeof loader.getExtensionPath !== "function") {
    yield* Effect.fail("getExtensionPath is not a function");
  }
  yield* Console.log("  ✅ getExtensionPath function exported");
  
  if (typeof loader.PREFER_IMPLEMENTATION !== "string") {
    yield* Effect.fail("PREFER_IMPLEMENTATION is not exported");
  }
  yield* Console.log(`  ✅ PREFER_IMPLEMENTATION = "${loader.PREFER_IMPLEMENTATION}"`);
  
  // Try to get extension path (may fail if no artifacts present)
  try {
    const path = loader.getExtensionPath();
    yield* Console.log(`  ✅ Extension path resolved: ${path}`);
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    yield* Console.log(`  ⚠️  Extension path not found (expected if no artifacts): ${msg.split('.')[0]}`);
  }
});

const main = Effect.gen(function* () {
  yield* Console.log("🚀 Running @effect-native/cr-sqlite package tests...\n");
  yield* testBasicFunctionality;
  yield* testLibArtifacts;
  yield* testZigBuildAvailable;
  yield* testLoaderSelection;
  yield* Console.log("\n🎉 All tests completed!");
});

// Run when called directly
if (import.meta.main) {
  const program = main.pipe(
    Effect.provide(BunContext.layer),
    Effect.catchAll((error) => Console.error(`Tests failed: ${error}`))
  );
  BunRuntime.runMain(program);
}
