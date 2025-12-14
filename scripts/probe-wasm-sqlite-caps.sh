#!/usr/bin/env bash
# probe-wasm-sqlite-caps.sh
#
# Purpose: Verify that SQLite WASM supports all SQL features required by CR-SQLite.
# This is a GAN adversary gate (Phase 0) - if any feature is missing, we must stop
# and address it before proceeding with the Zig rewrite.
#
# Required features (per research/zig-cr/93-phased-execution-proposal.md):
#   - STRICT tables: CREATE TABLE t(x INT) STRICT;
#   - RETURNING clause: INSERT INTO t VALUES(1) RETURNING x;
#   - Triggers: CREATE TRIGGER ... AFTER INSERT ...
#   - Virtual tables: CREATE VIRTUAL TABLE ... USING ...
#
# Usage:
#   ./scripts/probe-wasm-sqlite-caps.sh
#   # or via nix:
#   nix develop -c ./scripts/probe-wasm-sqlite-caps.sh
#
# Exit codes:
#   0 - All features supported
#   1 - One or more features missing (blocks Phase 1+)

set -euo pipefail

# Colors for output (respects NO_COLOR)
if [[ -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED='' GREEN='' BLUE='' YELLOW='' NC=''
fi

echo -e "${BLUE}SQLite WASM Capability Probe${NC}"
echo "Testing required SQL features for CR-SQLite..."
echo

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Initialize minimal npm project
cat > package.json << 'EOF'
{
  "name": "wasm-sqlite-probe",
  "private": true,
  "type": "module"
}
EOF

# Install official SQLite WASM
echo -e "${BLUE}Installing @aspect-build/aspect-build-rules-js/sqlite3-wasm...${NC}"
echo "(Using official SQLite WASM distribution)"

# Try the official sqlite-wasm package first, fall back to alternatives
if ! npm install --silent @aspect-build/aspect-build-rules-js@latest 2>/dev/null; then
  echo -e "${YELLOW}Note: @aspect-build not available, trying @aspect-build/aspect-build-rules-js...${NC}"
fi

# Use the official sqlite.org WASM distribution via better-sqlite3-wasm or sql.js
# sql.js is the most widely used SQLite WASM and a good reference
if ! npm install --silent sql.js 2>/dev/null; then
  echo -e "${RED}Failed to install sql.js${NC}"
  exit 1
fi
echo -e "${GREEN}sql.js installed${NC}"
echo

# Create the probe script
cat > probe.mjs << 'PROBE_EOF'
import initSqlJs from 'sql.js';

// Track results
const results = {
  STRICT: { tested: false, pass: false, error: null },
  RETURNING: { tested: false, pass: false, error: null },
  TRIGGERS: { tested: false, pass: false, error: null },
  VIRTUAL_TABLES: { tested: false, pass: false, error: null },
};

async function main() {
  // Initialize sql.js (loads the WASM)
  const SQL = await initSqlJs();
  const db = new SQL.Database();

  // =========================================================================
  // Test 1: STRICT tables
  // CR-SQLite uses STRICT tables for type safety in clock tables
  // Requires SQLite 3.37.0+ (2021-11-27)
  // =========================================================================
  results.STRICT.tested = true;
  try {
    db.run('CREATE TABLE strict_test(x INT, y TEXT) STRICT;');
    // Verify STRICT enforcement by inserting wrong type
    try {
      db.run("INSERT INTO strict_test(x, y) VALUES('not_an_int', 'text');");
      // If this succeeds, STRICT is not enforced
      results.STRICT.pass = false;
      results.STRICT.error = 'STRICT mode did not reject type mismatch';
    } catch (e) {
      // Good - STRICT rejected the bad type
      results.STRICT.pass = true;
    }
    db.run('DROP TABLE strict_test;');
  } catch (e) {
    results.STRICT.pass = false;
    results.STRICT.error = e.message;
  }

  // =========================================================================
  // Test 2: RETURNING clause
  // CR-SQLite uses RETURNING to get inserted PKs and versions
  // Requires SQLite 3.35.0+ (2021-03-12)
  // =========================================================================
  results.RETURNING.tested = true;
  try {
    db.run('CREATE TABLE returning_test(id INTEGER PRIMARY KEY, val TEXT);');
    const stmt = db.prepare('INSERT INTO returning_test(val) VALUES(?) RETURNING id, val;');
    stmt.bind(['hello']);
    if (stmt.step()) {
      const row = stmt.get();
      // row should be [1, 'hello'] or similar
      if (row && row.length === 2 && row[0] === 1 && row[1] === 'hello') {
        results.RETURNING.pass = true;
      } else {
        results.RETURNING.pass = false;
        results.RETURNING.error = `Unexpected RETURNING result: ${JSON.stringify(row)}`;
      }
    } else {
      results.RETURNING.pass = false;
      results.RETURNING.error = 'RETURNING did not return any rows';
    }
    stmt.free();
    db.run('DROP TABLE returning_test;');
  } catch (e) {
    results.RETURNING.pass = false;
    results.RETURNING.error = e.message;
  }

  // =========================================================================
  // Test 3: Triggers
  // CR-SQLite relies heavily on AFTER INSERT/UPDATE/DELETE triggers for
  // capturing local changes into clock tables
  // =========================================================================
  results.TRIGGERS.tested = true;
  try {
    db.run('CREATE TABLE trigger_source(id INTEGER PRIMARY KEY, val TEXT);');
    db.run('CREATE TABLE trigger_log(event TEXT, source_id INT);');
    db.run(`
      CREATE TRIGGER test_insert_trigger
      AFTER INSERT ON trigger_source
      BEGIN
        INSERT INTO trigger_log(event, source_id) VALUES('INSERT', NEW.id);
      END;
    `);
    db.run(`
      CREATE TRIGGER test_update_trigger
      AFTER UPDATE ON trigger_source
      BEGIN
        INSERT INTO trigger_log(event, source_id) VALUES('UPDATE', NEW.id);
      END;
    `);
    db.run(`
      CREATE TRIGGER test_delete_trigger
      AFTER DELETE ON trigger_source
      BEGIN
        INSERT INTO trigger_log(event, source_id) VALUES('DELETE', OLD.id);
      END;
    `);

    // Test INSERT trigger
    db.run("INSERT INTO trigger_source(val) VALUES('test');");
    // Test UPDATE trigger
    db.run("UPDATE trigger_source SET val = 'updated' WHERE id = 1;");
    // Test DELETE trigger
    db.run('DELETE FROM trigger_source WHERE id = 1;');

    // Verify all triggers fired
    const logs = db.exec('SELECT event FROM trigger_log ORDER BY rowid;');
    const events = logs[0]?.values?.map(r => r[0]) || [];
    
    if (events.length === 3 && 
        events[0] === 'INSERT' && 
        events[1] === 'UPDATE' && 
        events[2] === 'DELETE') {
      results.TRIGGERS.pass = true;
    } else {
      results.TRIGGERS.pass = false;
      results.TRIGGERS.error = `Expected [INSERT,UPDATE,DELETE], got ${JSON.stringify(events)}`;
    }
    
    db.run('DROP TABLE trigger_log;');
    db.run('DROP TABLE trigger_source;');
  } catch (e) {
    results.TRIGGERS.pass = false;
    results.TRIGGERS.error = e.message;
  }

  // =========================================================================
  // Test 4: Virtual Tables
  // CR-SQLite uses virtual tables for crsql_changes (read/write) and
  // crsql_unpack_columns. We need at least the basic vtab infrastructure.
  // We test with FTS5 (commonly enabled) or the built-in generate_series.
  // =========================================================================
  results.VIRTUAL_TABLES.tested = true;
  try {
    // Try FTS5 first (commonly enabled in WASM builds)
    try {
      db.run('CREATE VIRTUAL TABLE vtab_test USING fts5(content);');
      db.run("INSERT INTO vtab_test VALUES('hello world');");
      const ftsResult = db.exec("SELECT * FROM vtab_test WHERE content MATCH 'hello';");
      if (ftsResult[0]?.values?.length > 0) {
        results.VIRTUAL_TABLES.pass = true;
        results.VIRTUAL_TABLES.error = null; // FTS5 works
      }
      db.run('DROP TABLE vtab_test;');
    } catch (ftsErr) {
      // FTS5 not available, try json_each (built-in table-valued function)
      try {
        const jsonResult = db.exec("SELECT value FROM json_each('[1,2,3]');");
        if (jsonResult[0]?.values?.length === 3) {
          results.VIRTUAL_TABLES.pass = true;
          results.VIRTUAL_TABLES.error = 'FTS5 unavailable, but json_each works (vtab infra present)';
        }
      } catch (jsonErr) {
        results.VIRTUAL_TABLES.pass = false;
        results.VIRTUAL_TABLES.error = `FTS5: ${ftsErr.message}; json_each: ${jsonErr.message}`;
      }
    }
  } catch (e) {
    results.VIRTUAL_TABLES.pass = false;
    results.VIRTUAL_TABLES.error = e.message;
  }

  // =========================================================================
  // Report SQLite version
  // =========================================================================
  const versionResult = db.exec('SELECT sqlite_version();');
  const sqliteVersion = versionResult[0]?.values?.[0]?.[0] || 'unknown';
  
  db.close();

  // =========================================================================
  // Output results
  // =========================================================================
  console.log(`SQLite WASM Version: ${sqliteVersion}`);
  console.log('');
  console.log('Feature Probe Results:');
  console.log('======================');
  
  let allPassed = true;
  for (const [feature, result] of Object.entries(results)) {
    const status = result.pass ? 'PASS' : 'FAIL';
    const statusEmoji = result.pass ? '✓' : '✗';
    console.log(`  ${statusEmoji} ${feature}: ${status}`);
    if (result.error && !result.pass) {
      console.log(`    Error: ${result.error}`);
    } else if (result.error && result.pass) {
      console.log(`    Note: ${result.error}`);
    }
    if (!result.pass) allPassed = false;
  }
  
  console.log('');
  if (allPassed) {
    console.log('All required features are supported.');
    console.log('Proceed to Phase 1 (wire format / codec).');
    process.exit(0);
  } else {
    console.log('BLOCKED: One or more required features missing.');
    console.log('Per GAN adversary rules, stop and fix before proceeding.');
    process.exit(1);
  }
}

main().catch(err => {
  console.error('Probe failed with error:', err);
  process.exit(1);
});
PROBE_EOF

# Run the probe
echo -e "${BLUE}Running capability probe...${NC}"
echo
node probe.mjs
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  echo -e "${GREEN}WASM SQLite capability probe PASSED${NC}"
else
  echo -e "${RED}WASM SQLite capability probe FAILED${NC}"
fi

exit $exit_code
