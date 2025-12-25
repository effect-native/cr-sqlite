#!/usr/bin/env -S npx tsx

import { Console, Effect } from "effect";
import { Command, FileSystem, Path } from "@effect/platform";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface PackageJson {
  version: string;
  [key: string]: unknown;
}

const getCRSQLiteVersion = Effect.gen(function* () {
  yield* Console.log("🔍 Getting CR-SQLite version from Nix...");

  const result = yield* Command.make("nix", "run", ".#print-version").pipe(
    Command.string,
    Effect.withSpan("getCRSQLiteVersion"),
    Effect.mapError(() => new Error("Failed to get CR-SQLite version from Nix")),
  );

  const version = result.trim();
  yield* Console.log(`📋 CR-SQLite version from Nix: ${version}`);
  return version;
});

const updatePackageVersion = (crSqliteVersion: string) =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    const projectRoot = path.resolve(__dirname, "..");
    const packageJsonPath = path.resolve(projectRoot, "package.json");

    const packageJsonContent = yield* fs.readFileString(packageJsonPath);
    const packageJson: PackageJson = JSON.parse(packageJsonContent);

    const currentVersion = packageJson.version;

    // If CR-SQLite version already includes a prerelease tag (e.g., "0.16.300-preview"),
    // use it directly as the canonical version. Don't append "-1".
    const isPrerelease = crSqliteVersion.includes('-');
    
    if (isPrerelease) {
      // For prerelease versions, the Nix version IS the canonical version
      if (currentVersion === crSqliteVersion) {
        yield* Console.log(`✅ Version already matches: ${currentVersion}`);
        return false;
      }
      
      yield* Console.log(
        `📦 Updating to prerelease version: ${currentVersion} → ${crSqliteVersion}`,
      );
      packageJson.version = crSqliteVersion;
    } else {
      // For stable versions, parse and compare base versions
      const [currentBase, _currentSuffix] = currentVersion.includes('-') 
        ? currentVersion.split('-', 2)
        : [currentVersion, null];
      
      // If CR-SQLite base version matches, keep the current version (including any suffix)
      if (currentBase === crSqliteVersion) {
        yield* Console.log(`✅ CR-SQLite version matches (${currentBase}), keeping current version: ${currentVersion}`);
        return false;
      }
      
      // If CR-SQLite version changed, update to new base version with -1 suffix
      const newVersion = `${crSqliteVersion}-1`;

      yield* Console.log(
        `📦 Updating to new CR-SQLite version: ${currentVersion} → ${newVersion}`,
      );
      packageJson.version = newVersion;
    }

    const updatedContent = JSON.stringify(packageJson, null, 2) + "\n";
    yield* fs.writeFileString(packageJsonPath, updatedContent);

    return true;
  });

const main = Effect.gen(function* () {
  yield* Console.log("🔍 Syncing package version with CR-SQLite version...");

  const crSqliteVersion = yield* getCRSQLiteVersion;
  const wasUpdated = yield* updatePackageVersion(crSqliteVersion);

  if (wasUpdated) {
    yield* Console.log("✨ Package version synced successfully!");
    yield* Console.log("💡 Don't forget to commit the changes.");
  }
});

// Run when called directly - lazy import Bun platform
if (import.meta.main) {
  const { BunContext, BunRuntime } = await import("@effect/platform-bun");
  const program = main.pipe(Effect.provide(BunContext.layer));
  BunRuntime.runMain(program);
}