/**
 * CR-SQLite Demo with bun:sqlite
 * 
 * Demonstrates:
 * - Loading a custom SQLite library that supports extensions
 * - Loading the CR-SQLite extension with bun:sqlite
 * - Creating CRR (conflict-free replicated relation) tables
 * - Basic CRUD operations
 * - Querying db_version
 * 
 * Run: bun run scratch/bun-scratchpad/index.ts
 */

import { Database } from "bun:sqlite";
import { resolve } from "node:path";
import { existsSync } from "node:fs";

// ─────────────────────────────────────────────────────────────────────────────
// Path Helpers
// ─────────────────────────────────────────────────────────────────────────────

function getPlatformInfo(): { platform: string; arch: string; ext: string } {
  const platform = process.platform === "darwin" ? "darwin" : "linux";
  const arch = process.arch === "arm64" ? "aarch64" : "x86_64";
  const ext = platform === "darwin" ? "dylib" : "so";
  return { platform, arch, ext };
}

// Find the custom libsqlite3 that supports extension loading
// This is from the effect-native/packages-native/libsqlite package
function getLibSqlitePath(): string {
  const { platform, arch, ext } = getPlatformInfo();
  
  const libSqliteDir = resolve(
    import.meta.dir, 
    "..", "..", 
    "effect-native/packages-native/libsqlite/lib",
    `${platform}-${arch}`
  );
  
  const libSqlitePath = resolve(libSqliteDir, `libsqlite3.${ext}`);
  
  if (existsSync(libSqlitePath)) {
    return libSqlitePath;
  }
  
  throw new Error(`libsqlite3 not found at ${libSqlitePath}. Run 'pnpm build' in effect-native first.`);
}

// Find the CR-SQLite extension
// Prefers the Zig-built extension which has the standard sqlite3_extension_init entry point
function getCrSqliteExtensionPath(): string {
  const { platform, arch, ext } = getPlatformInfo();
  const libDir = resolve(import.meta.dir, "..", "..", "lib");
  
  // Try Zig-built extension first (has standard sqlite3_extension_init)
  const zigExt = resolve(libDir, `crsqlite-zig-${platform}-${arch}.${ext}`);
  if (existsSync(zigExt)) {
    return zigExt;
  }
  
  // Try platform-specific Rust extension
  const specificExt = resolve(libDir, `crsqlite-${platform}-${arch}.${ext}`);
  if (existsSync(specificExt)) {
    return specificExt;
  }
  
  // Fallback to generic extensions
  const fallbackCandidates = [
    resolve(libDir, `crsqlite.${ext}`),
    resolve(libDir, "crsqlite.dylib"),
    resolve(libDir, "crsqlite.so"),
  ];
  
  for (const candidate of fallbackCandidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  
  throw new Error(`CR-SQLite extension not found for ${platform}/${arch}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Demo
// ─────────────────────────────────────────────────────────────────────────────

console.log("=== CR-SQLite Demo with bun:sqlite ===\n");

// 1. Load custom SQLite library that supports extensions
const libSqlitePath = getLibSqlitePath();
console.log(`1. Loading custom libsqlite3 from: ${libSqlitePath}`);
Database.setCustomSQLite(libSqlitePath);

// 2. Create an in-memory database
const db = new Database(":memory:");
console.log("2. Created in-memory SQLite database");

// Verify SQLite version
const sqliteVersion = db.query("SELECT sqlite_version() AS version").get() as { version: string };
console.log(`   SQLite version: ${sqliteVersion.version}`);

// 3. Load the CR-SQLite extension
const extensionPath = getCrSqliteExtensionPath();
console.log(`\n3. Loading CR-SQLite extension from: ${extensionPath}`);
db.loadExtension(extensionPath);

// Verify extension loaded
const extVersion = db.query("SELECT crsql_version()").get() as { "crsql_version()": string };
console.log(`   Extension loaded! Version: ${extVersion["crsql_version()"]}`);

// 4. Create a regular table
console.log("\n4. Creating 'items' table...");
db.run(`
  CREATE TABLE items (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    quantity INTEGER DEFAULT 0
  )
`);

// 5. Convert to CRR (conflict-free replicated relation)
console.log("5. Converting to CRR with crsql_as_crr('items')...");
db.run("SELECT crsql_as_crr('items')");
console.log("   Table is now a CRR!");

// 6. Show initial db_version
const initialVersion = db.query("SELECT crsql_db_version()").get() as { "crsql_db_version()": number };
console.log(`\n6. Initial db_version: ${initialVersion["crsql_db_version()"]}`);

// 7. Insert some data
console.log("\n7. Inserting items...");
const insertStmt = db.prepare("INSERT INTO items (id, name, quantity) VALUES (?, ?, ?)");

insertStmt.run("item-1", "Apples", 10);
console.log("   Inserted: Apples (qty: 10)");

insertStmt.run("item-2", "Bananas", 5);
console.log("   Inserted: Bananas (qty: 5)");

insertStmt.run("item-3", "Oranges", 8);
console.log("   Inserted: Oranges (qty: 8)");

// 8. Check db_version after inserts
const afterInsertVersion = db.query("SELECT crsql_db_version()").get() as { "crsql_db_version()": number };
console.log(`\n8. db_version after inserts: ${afterInsertVersion["crsql_db_version()"]}`);

// 9. Query all items
console.log("\n9. Querying all items:");
const items = db.query("SELECT * FROM items ORDER BY name").all() as Array<{ id: string; name: string; quantity: number }>;
for (const item of items) {
  console.log(`   - ${item.name}: ${item.quantity} (id: ${item.id})`);
}

// 10. Update an item
console.log("\n10. Updating Apples quantity to 15...");
db.run("UPDATE items SET quantity = 15 WHERE id = 'item-1'");

const afterUpdateVersion = db.query("SELECT crsql_db_version()").get() as { "crsql_db_version()": number };
console.log(`    db_version after update: ${afterUpdateVersion["crsql_db_version()"]}`);

// 11. Delete an item
console.log("\n11. Deleting Oranges...");
db.run("DELETE FROM items WHERE id = 'item-3'");

const afterDeleteVersion = db.query("SELECT crsql_db_version()").get() as { "crsql_db_version()": number };
console.log(`    db_version after delete: ${afterDeleteVersion["crsql_db_version()"]}`);

// 12. Final query
console.log("\n12. Final items:");
const finalItems = db.query("SELECT * FROM items ORDER BY name").all() as Array<{ id: string; name: string; quantity: number }>;
for (const item of finalItems) {
  console.log(`    - ${item.name}: ${item.quantity}`);
}

// 13. Show change tracking (crsql_changes virtual table)
console.log("\n13. Changes tracked in crsql_changes (since version 0):");
const changes = db.query(`
  SELECT [table], pk, cid, val, db_version, site_id 
  FROM crsql_changes 
  WHERE db_version > 0
  ORDER BY db_version
`).all() as Array<{ table: string; pk: unknown; cid: string; val: unknown; db_version: number; site_id: Uint8Array }>;

for (const change of changes) {
  console.log(`    v${change.db_version}: ${change.table}.${change.cid} = ${change.val} (pk: ${change.pk})`);
}

// 14. Show site_id (unique identifier for this database instance)
const siteIdResult = db.query("SELECT crsql_site_id()").get() as { "crsql_site_id()": Uint8Array };
const siteId = Buffer.from(siteIdResult["crsql_site_id()"]).toString("hex");
console.log(`\n14. This database's site_id: ${siteId}`);

// Cleanup
db.run("SELECT crsql_finalize()");
db.close();

console.log("\n=== Demo complete! ===");
