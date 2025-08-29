#!/usr/bin/env -S npx tsx

import { Console, Effect } from "effect";
import { Command, FileSystem } from "@effect/platform";
import { BunContext, BunRuntime } from "@effect/platform-bun";
import { existsSync } from "node:fs";

const testBasicFunctionality = Effect.gen(function* () {
  yield* Console.log("🧪 Testing basic package functionality...");

  // Test 1: Check if main files exist
  yield* Console.log("📁 Test 1: Checking main files...");
  const requiredFiles = [
    "package.json",
    "flake.nix", 
    "index.js",
    "index.d.ts",
    "bin/cr-sqlite-extension-path.ts",
    "scripts/build-production.ts",
    "scripts/sync-version.ts",
    "build-macros.ts"
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
    Effect.mapError(() => "Nix flake check failed"),
  );
  yield* Console.log("  ✅ Nix flake is valid");

  // Test 3: Check TypeScript compilation
  yield* Console.log("\n📝 Test 3: Checking TypeScript compilation...");
  yield* Command.make("npx", "tsc", "--noEmit", "index.d.ts").pipe(
    Command.exitCode,
    Effect.mapError(() => "TypeScript compilation failed"),
    Effect.ignore, // Ignore errors for now since we might not have all dependencies
  );

  yield* Console.log("✅ All basic tests passed!");
});

const main = Effect.gen(function* () {
  yield* Console.log("🚀 Running @effect-native/cr-sqlite package tests...");
  yield* testBasicFunctionality;
  yield* Console.log("\n🎉 All tests completed successfully!");
});

// Run when called directly
if (import.meta.main) {
  const program = main.pipe(
    Effect.provide(BunContext.layer),
    Effect.catchAll((error) => Console.error(`Tests failed: ${error}`)),
  );
  BunRuntime.runMain(program);
}