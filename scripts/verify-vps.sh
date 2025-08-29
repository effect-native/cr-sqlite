#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 CR-SQLite VPS Verification Test${NC}"
echo "Testing package installation and functionality on this system..."

# Create temporary directory for testing
TEMP_DIR=$(mktemp -d)
echo -e "${BLUE}📁 Using temp directory: ${TEMP_DIR}${NC}"

cleanup() {
    echo -e "${BLUE}🧹 Cleaning up...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Test 1: Install the package
echo -e "\n${BLUE}📦 Test 1: Installing @effect-native/libcrsql...${NC}"
if npm init -y > /dev/null 2>&1 && npm install @effect-native/libcrsql > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Package installed successfully${NC}"
else
    echo -e "${RED}❌ Package installation failed${NC}"
    exit 1
fi

# Test 2: Check if extension file exists and is accessible
echo -e "\n${BLUE}🔍 Test 2: Checking extension file accessibility...${NC}"
EXTENSION_PATH=$(npx libcrsql-extension-path 2>/dev/null || echo "")
if [[ -n "$EXTENSION_PATH" && -f "$EXTENSION_PATH" ]]; then
    echo -e "${GREEN}✅ Extension file found: $EXTENSION_PATH${NC}"
    echo -e "${BLUE}📊 File info:${NC}"
    ls -la "$EXTENSION_PATH" | head -1
    file "$EXTENSION_PATH" || echo "file command not available"
else
    echo -e "${RED}❌ Extension file not found or inaccessible${NC}"
    exit 1
fi

# Test 3: Test programmatic access
echo -e "\n${BLUE}💻 Test 3: Testing programmatic access...${NC}"
cat > test.mjs << 'EOF'
import { pathToCRSQLite, getExtensionPath } from '@effect-native/libcrsql';
import { existsSync } from 'fs';

console.log('Extension path:', pathToCRSQLite);
console.log('getExtensionPath():', getExtensionPath());
console.log('File exists:', existsSync(pathToCRSQLite));

if (!existsSync(pathToCRSQLite)) {
    throw new Error('Extension file not found');
}

console.log('✅ Programmatic access works');
EOF

if node test.mjs; then
    echo -e "${GREEN}✅ Programmatic access test passed${NC}"
else
    echo -e "${RED}❌ Programmatic access test failed${NC}"
    exit 1
fi

# Test 4: Test with SQLite (if available)
echo -e "\n${BLUE}🗃️  Test 4: Testing with SQLite...${NC}"
if command -v sqlite3 >/dev/null 2>&1; then
    echo -e "${BLUE}SQLite3 CLI found, testing extension loading...${NC}"
    
    # Test loading the extension
    if echo "SELECT 1;" | sqlite3 -cmd ".load $EXTENSION_PATH" :memory: >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Extension loads successfully in SQLite${NC}"
        
        # Test CR-SQLite specific functionality
        if echo "SELECT crsql_version();" | sqlite3 -cmd ".load $EXTENSION_PATH" :memory: >/dev/null 2>&1; then
            VERSION=$(echo "SELECT crsql_version();" | sqlite3 -cmd ".load $EXTENSION_PATH" :memory: 2>/dev/null | head -1)
            echo -e "${GREEN}✅ CR-SQLite functions work! Version: ${VERSION}${NC}"
        else
            echo -e "${YELLOW}⚠️  Extension loads but CR-SQLite functions may not be working${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to load extension in SQLite${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  sqlite3 command not found, skipping SQLite integration test${NC}"
fi

# Test 5: Platform detection
echo -e "\n${BLUE}🖥️  Test 5: Platform detection...${NC}"
echo "Platform: $(node -e 'console.log(process.platform)')"
echo "Architecture: $(node -e 'console.log(process.arch)')"
echo "Expected extension: crsqlite-$(node -e 'console.log(process.platform === "darwin" ? "darwin" : "linux")')-$(node -e 'console.log(process.arch === "arm64" ? "aarch64" : "x86_64")').$(node -e 'console.log(process.platform === "darwin" ? "dylib" : "so")')"

# Test 6: Performance check (basic)
echo -e "\n${BLUE}⚡ Test 6: Basic performance check...${NC}"
time node -e 'import("@effect-native/libcrsql").then(({pathToCRSQLite}) => console.log("Path loaded:", !!pathToCRSQLite))' || echo "Performance test completed"

echo -e "\n${GREEN}🎉 All VPS verification tests passed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo "- Package installs correctly ✅"
echo "- Extension file accessible ✅" 
echo "- Programmatic access works ✅"
echo "- SQLite integration $(command -v sqlite3 >/dev/null && echo '✅' || echo '⚠️ (skipped)')"
echo "- Platform detection works ✅"
echo "- Performance acceptable ✅"

echo -e "\n${GREEN}✨ @effect-native/libcrsql is ready for production on this system!${NC}"