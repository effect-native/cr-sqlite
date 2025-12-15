# 104-mobile-static-embedding-guide

Guide for statically embedding CR-SQLite into iOS and Android applications.

## Why Static Embedding?

Dynamic extension loading (`sqlite3_load_extension()`) is unavailable or restricted on mobile platforms:

| Platform | Dynamic Loading | Reason |
|----------|-----------------|--------|
| iOS | ❌ Blocked | App Store prohibits loading unsigned code at runtime |
| Android | ⚠️ Limited | `sqlite3_load_extension` often disabled in system SQLite; custom builds required |
| Web/WASM | ❌ N/A | No dynamic linking in WASM; extensions must be compiled in |

The solution: **link CR-SQLite as a static library** and call the init symbol directly when opening each connection.

## Build Targets

The Zig build system produces cross-platform static libraries:

```bash
cd zig

# iOS arm64
nix run nixpkgs#zig -- build -Dtarget=aarch64-ios -Doptimize=ReleaseSafe

# iOS Simulator (arm64 for Apple Silicon Macs)
nix run nixpkgs#zig -- build -Dtarget=aarch64-ios-simulator -Doptimize=ReleaseSafe

# iOS Simulator (x86_64 for Intel Macs)
nix run nixpkgs#zig -- build -Dtarget=x86_64-ios-simulator -Doptimize=ReleaseSafe

# Android arm64-v8a
nix run nixpkgs#zig -- build -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe

# Android armeabi-v7a
nix run nixpkgs#zig -- build -Dtarget=arm-linux-androideabi -Doptimize=ReleaseSafe

# Android x86_64 (emulator)
nix run nixpkgs#zig -- build -Dtarget=x86_64-linux-android -Doptimize=ReleaseSafe
```

Output: `zig-out/lib/libcrsql.a`

## iOS Integration

### 1. Create XCFramework (optional, but recommended)

Combine architectures into an XCFramework for easier distribution:

```bash
# Build all iOS slices
for target in aarch64-ios aarch64-ios-simulator x86_64-ios-simulator; do
  nix run nixpkgs#zig -- build -Dtarget=$target -Doptimize=ReleaseSafe
  mkdir -p build/$target
  cp zig-out/lib/libcrsql.a build/$target/
done

# Create fat library for simulator (arm64 + x86_64)
lipo -create \
  build/aarch64-ios-simulator/libcrsql.a \
  build/x86_64-ios-simulator/libcrsql.a \
  -output build/ios-simulator/libcrsql.a

# Create XCFramework
xcodebuild -create-xcframework \
  -library build/aarch64-ios/libcrsql.a \
  -library build/ios-simulator/libcrsql.a \
  -output CRSQLite.xcframework
```

### 2. Add to Xcode Project

1. Drag `CRSQLite.xcframework` (or `libcrsql.a`) into your Xcode project
2. Ensure "Link Binary with Libraries" includes the framework
3. Add to "Library Search Paths" if using `.a` directly

### 3. Initialize Per Connection

The init function signature (from `zig/src/root.zig`):

```c
int sqlite3_crsqlite_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
);
```

Swift initialization:

```swift
import SQLite3

// Declare the init symbol (extern)
@_silgen_name("sqlite3_crsqlite_init")
func sqlite3_crsqlite_init(
    _ db: OpaquePointer?,
    _ pzErrMsg: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ pApi: OpaquePointer?
) -> Int32

class CRSQLiteConnection {
    private var db: OpaquePointer?
    
    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw SQLiteError.openFailed
        }
        
        // Initialize CR-SQLite extension
        // Pass nil for pApi when calling directly (not via load_extension)
        let rc = sqlite3_crsqlite_init(db, nil, nil)
        guard rc == SQLITE_OK else {
            sqlite3_close(db)
            throw SQLiteError.extensionInitFailed(rc)
        }
    }
    
    deinit {
        // IMPORTANT: Finalize CR-SQLite before closing
        sqlite3_exec(db, "SELECT crsql_finalize()", nil, nil, nil)
        sqlite3_close(db)
    }
}
```

Objective-C initialization:

```objc
// Declare extern
extern int sqlite3_crsqlite_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi);

- (BOOL)openDatabaseAtPath:(NSString *)path error:(NSError **)error {
    int rc = sqlite3_open([path UTF8String], &_db);
    if (rc != SQLITE_OK) {
        // handle error
        return NO;
    }
    
    // Initialize CR-SQLite
    rc = sqlite3_crsqlite_init(_db, NULL, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_close(_db);
        // handle error
        return NO;
    }
    
    return YES;
}

- (void)close {
    if (_db) {
        // IMPORTANT: Finalize before close
        sqlite3_exec(_db, "SELECT crsql_finalize()", NULL, NULL, NULL);
        sqlite3_close(_db);
        _db = NULL;
    }
}
```

## Android Integration

### 1. Build for NDK Targets

```bash
# Create directory structure matching Android ABI naming
mkdir -p android-libs/{arm64-v8a,armeabi-v7a,x86_64,x86}

# arm64-v8a (most devices)
nix run nixpkgs#zig -- build -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe
cp zig-out/lib/libcrsql.a android-libs/arm64-v8a/

# armeabi-v7a (older devices)
nix run nixpkgs#zig -- build -Dtarget=arm-linux-androideabi -Doptimize=ReleaseSafe
cp zig-out/lib/libcrsql.a android-libs/armeabi-v7a/

# x86_64 (emulator)
nix run nixpkgs#zig -- build -Dtarget=x86_64-linux-android -Doptimize=ReleaseSafe
cp zig-out/lib/libcrsql.a android-libs/x86_64/

# x86 (old emulator)
nix run nixpkgs#zig -- build -Dtarget=x86-linux-android -Doptimize=ReleaseSafe
cp zig-out/lib/libcrsql.a android-libs/x86/
```

### 2. CMake Integration

Add to your `CMakeLists.txt`:

```cmake
# Find the prebuilt static library for current ABI
set(CRSQL_LIB_DIR ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI})

add_library(crsql STATIC IMPORTED)
set_target_properties(crsql PROPERTIES
    IMPORTED_LOCATION ${CRSQL_LIB_DIR}/libcrsql.a
)

# Link to your JNI library
target_link_libraries(your-jni-lib
    crsql
    # ... other deps
)
```

### 3. JNI Initialization

Create a JNI wrapper that initializes CR-SQLite per connection:

```c
// crsql_jni.c
#include <jni.h>
#include <sqlite3.h>

// Declare the init symbol
extern int sqlite3_crsqlite_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi);

JNIEXPORT jlong JNICALL
Java_com_example_CRSQLite_nativeOpen(JNIEnv *env, jclass cls, jstring path) {
    const char *pathStr = (*env)->GetStringUTFChars(env, path, NULL);
    sqlite3 *db = NULL;
    
    int rc = sqlite3_open(pathStr, &db);
    (*env)->ReleaseStringUTFChars(env, path, pathStr);
    
    if (rc != SQLITE_OK) {
        return 0;
    }
    
    // Initialize CR-SQLite extension
    rc = sqlite3_crsqlite_init(db, NULL, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        return 0;
    }
    
    return (jlong)db;
}

JNIEXPORT void JNICALL
Java_com_example_CRSQLite_nativeClose(JNIEnv *env, jclass cls, jlong dbPtr) {
    sqlite3 *db = (sqlite3 *)dbPtr;
    if (db) {
        // IMPORTANT: Finalize before close
        sqlite3_exec(db, "SELECT crsql_finalize()", NULL, NULL, NULL);
        sqlite3_close(db);
    }
}
```

Kotlin wrapper:

```kotlin
object CRSQLite {
    init {
        System.loadLibrary("your-jni-lib")
    }
    
    external fun nativeOpen(path: String): Long
    external fun nativeClose(dbPtr: Long)
    
    fun open(path: String): Long {
        val ptr = nativeOpen(path)
        if (ptr == 0L) {
            throw RuntimeException("Failed to open CR-SQLite database")
        }
        return ptr
    }
}
```

### Android Note: SQLite Version

Android's system SQLite may lack features CR-SQLite requires (e.g., `RETURNING`, certain vtab APIs). Consider bundling SQLite:

- Use [SQLCipher](https://www.zetetic.net/sqlcipher/sqlcipher-for-android/) (includes modern SQLite)
- Or compile SQLite from source with NDK alongside `libcrsql.a`

## Validation Strategy

Since mobile builds cannot easily run in CI, use this validation approach:

### 1. Native Host Smoke Test

Verify the static library works on the host before cross-compiling:

```bash
cd zig

# Build for host
nix run nixpkgs#zig -- build

# Verify symbols are exported
nm zig-out/lib/libcrsql.a | grep sqlite3_crsqlite_init
# Expected: T _sqlite3_crsqlite_init (or similar)

# Run unit tests
make test-unit
```

### 2. Cross-Compile Symbol Check

After building for mobile targets, verify the init symbol is present:

```bash
# iOS
nm build/aarch64-ios/libcrsql.a | grep crsqlite_init

# Android (requires NDK toolchain in PATH)
llvm-nm android-libs/arm64-v8a/libcrsql.a | grep crsqlite_init
```

### 3. Minimal "Hello" Test App

Create a minimal test app for each platform that:

1. Opens an in-memory database
2. Calls `sqlite3_crsqlite_init()`
3. Runs `SELECT crsql_version()`
4. Verifies the result is non-empty

iOS (SwiftUI):

```swift
struct ContentView: View {
    @State var result = "Testing..."
    
    var body: some View {
        Text(result)
            .onAppear {
                var db: OpaquePointer?
                guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
                    result = "❌ open failed"
                    return
                }
                guard sqlite3_crsqlite_init(db, nil, nil) == SQLITE_OK else {
                    result = "❌ init failed"
                    return
                }
                
                var stmt: OpaquePointer?
                sqlite3_prepare_v2(db, "SELECT crsql_version()", -1, &stmt, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let version = String(cString: sqlite3_column_text(stmt, 0))
                    result = "✅ CR-SQLite v\(version)"
                }
                sqlite3_finalize(stmt)
                sqlite3_exec(db, "SELECT crsql_finalize()", nil, nil, nil)
                sqlite3_close(db)
            }
    }
}
```

Android (Kotlin):

```kotlin
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val result = try {
            val dbPtr = CRSQLite.open(":memory:")
            // Execute SELECT crsql_version() via your SQLite binding
            // ...
            CRSQLite.nativeClose(dbPtr)
            "✅ CR-SQLite initialized"
        } catch (e: Exception) {
            "❌ ${e.message}"
        }
        
        setContentView(TextView(this).apply { text = result })
    }
}
```

### 4. Integration Test Checklist

Once the hello app works, verify core functionality:

- [ ] `SELECT crsql_version()` returns expected version
- [ ] `SELECT hex(crsql_site_id())` returns 32-char hex string
- [ ] `CREATE TABLE t (id INTEGER PRIMARY KEY); SELECT crsql_as_crr('t')` succeeds
- [ ] `INSERT INTO t VALUES (1)` followed by `SELECT * FROM crsql_changes` returns 1 row
- [ ] `SELECT crsql_finalize()` before close completes without error

## Common Issues

### Symbol Not Found

If linking fails with "undefined symbol sqlite3_crsqlite_init":

1. Verify the library is linked: check Xcode's "Link Binary with Libraries" or CMake's `target_link_libraries`
2. Verify the symbol exists: `nm libcrsql.a | grep crsqlite`
3. For iOS, ensure the correct architecture slice is included

### SQLite Version Mismatch

CR-SQLite requires SQLite 3.35+ for `RETURNING` clause support. Mobile system SQLite may be older:

- iOS 15+: SQLite 3.36+ (OK)
- Android: Varies by device (often older)

Solution: Bundle a known SQLite version with your app.

### Missing pApi Routines

When calling `sqlite3_crsqlite_init(db, NULL, NULL)`:

- The third parameter (`pApi`) is only used when loading via `sqlite3_load_extension()`
- For static linking, pass `NULL` — the extension uses direct SQLite calls instead

## References

- [SQLite Run-Time Loadable Extensions](https://sqlite.org/loadext.html)
- [Zig Cross-Compilation](https://ziglang.org/documentation/master/#Cross-compilation)
- Build config: `zig/build.zig`
- Platform notes: `research/zig-cr/93-phased-execution-proposal.md`
