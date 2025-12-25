// src/shared/rpc-types.ts
function createResultResponse(requestId, result) {
  return { type: "result", requestId, payload: { result } };
}
function createErrorResponse(requestId, code, message) {
  return { type: "error", requestId, payload: { code, message } };
}

// src/provider/worker.ts
console.log("[ProviderWorker] Starting...");
var SQLITE_OK = 0;
var SQLITE_ROW = 100;
var SQLITE_DONE = 101;
var SQLITE_INTEGER = 1;
var SQLITE_FLOAT = 2;
var SQLITE_TEXT = 3;
var SQLITE_BLOB = 4;
var SQLITE_NULL = 5;
var SQLITE_TRANSIENT = -1;
var CrSqliteDatabase = class {
  mod;
  dbPtr;
  constructor(mod, data) {
    this.mod = mod;
    const ppDb = mod._malloc(4);
    const filenamePtr = mod._malloc(9);
    mod.stringToUTF8(":memory:", filenamePtr, 9);
    const rc = mod._sqlite3_open(filenamePtr, ppDb);
    mod._free(filenamePtr);
    if (rc !== SQLITE_OK) {
      mod._free(ppDb);
      throw new Error(`Failed to open database: rc=${rc}`);
    }
    this.dbPtr = mod.getValue(ppDb, "i32");
    mod._free(ppDb);
    if (data && data.length > 0) {
      this.deserialize(data);
    }
  }
  deserialize(data) {
    const { mod, dbPtr } = this;
    console.log("[CrSqliteDatabase.deserialize] Deserializing", data.length, "bytes");
    const size = data.length;
    const dataPtr = mod._malloc(size);
    for (let i = 0; i < size; i++) {
      mod.HEAPU8[dataPtr + i] = data[i];
    }
    const schemaPtr = mod._malloc(5);
    mod.stringToUTF8("main", schemaPtr, 5);
    const flags = 1 | 2;
    const rc = mod._sqlite3_deserialize(dbPtr, schemaPtr, dataPtr, BigInt(size), BigInt(size), flags);
    mod._free(schemaPtr);
    if (rc !== SQLITE_OK) {
      mod._free(dataPtr);
      console.error("[CrSqliteDatabase.deserialize] Failed with rc:", rc);
      throw new Error(`Failed to deserialize database: rc=${rc}`);
    }
    console.log("[CrSqliteDatabase.deserialize] Successfully deserialized");
  }
  run(sql, params) {
    this.execInternal(sql, params, false);
  }
  exec(sql) {
    return this.execInternal(sql, void 0, true);
  }
  execInternal(sql, params, returnResults) {
    const { mod, dbPtr } = this;
    const results = [];
    const sqlLen = mod.lengthBytesUTF8(sql) + 1;
    const sqlPtr = mod._malloc(sqlLen);
    mod.stringToUTF8(sql, sqlPtr, sqlLen);
    const ppStmt = mod._malloc(4);
    const pzTail = mod._malloc(4);
    let currentSqlPtr = sqlPtr;
    try {
      while (true) {
        const rc = mod._sqlite3_prepare_v2(dbPtr, currentSqlPtr, -1, ppStmt, pzTail);
        if (rc !== SQLITE_OK) {
          const errMsg = mod.UTF8ToString(mod._sqlite3_errmsg(dbPtr));
          throw new Error(`SQLite prepare error: ${errMsg}`);
        }
        const stmtPtr = mod.getValue(ppStmt, "i32");
        if (stmtPtr === 0) {
          break;
        }
        try {
          if (params && results.length === 0) {
            this.bindParams(stmtPtr, params);
          }
          const colCount = mod._sqlite3_column_count(stmtPtr);
          const columns = [];
          if (returnResults && colCount > 0) {
            for (let i = 0; i < colCount; i++) {
              const namePtr = mod._sqlite3_column_name(stmtPtr, i);
              columns.push(namePtr ? mod.UTF8ToString(namePtr) : `col${i}`);
            }
          }
          const values = [];
          let stepRc;
          while ((stepRc = mod._sqlite3_step(stmtPtr)) === SQLITE_ROW) {
            if (returnResults && colCount > 0) {
              const row = [];
              for (let i = 0; i < colCount; i++) {
                row.push(this.getColumnValue(stmtPtr, i));
              }
              values.push(row);
            }
          }
          if (stepRc !== SQLITE_DONE) {
            const errMsg = mod.UTF8ToString(mod._sqlite3_errmsg(dbPtr));
            throw new Error(`SQLite step error: ${errMsg}`);
          }
          if (returnResults && colCount > 0) {
            results.push({ columns, values });
          }
        } finally {
          mod._sqlite3_finalize(stmtPtr);
        }
        const tailPtr = mod.getValue(pzTail, "i32");
        if (tailPtr === 0 || tailPtr === currentSqlPtr) {
          break;
        }
        const remaining = mod.UTF8ToString(tailPtr).trim();
        if (!remaining) {
          break;
        }
        currentSqlPtr = tailPtr;
      }
    } finally {
      mod._free(sqlPtr);
      mod._free(ppStmt);
      mod._free(pzTail);
    }
    return results;
  }
  bindParams(stmtPtr, params) {
    const { mod } = this;
    for (let i = 0; i < params.length; i++) {
      const param = params[i];
      const idx = i + 1;
      let rc;
      if (param === null || param === void 0) {
        rc = mod._sqlite3_bind_null(stmtPtr, idx);
      } else if (typeof param === "number") {
        if (Number.isInteger(param)) {
          rc = mod._sqlite3_bind_int(stmtPtr, idx, param);
        } else {
          rc = mod._sqlite3_bind_double(stmtPtr, idx, param);
        }
      } else if (typeof param === "string") {
        const len = mod.lengthBytesUTF8(param);
        const ptr = mod._malloc(len + 1);
        mod.stringToUTF8(param, ptr, len + 1);
        rc = mod._sqlite3_bind_text(stmtPtr, idx, ptr, len, SQLITE_TRANSIENT);
        mod._free(ptr);
      } else if (param instanceof Uint8Array || param instanceof ArrayBuffer) {
        const bytes = param instanceof ArrayBuffer ? new Uint8Array(param) : param;
        const ptr = mod._malloc(bytes.length);
        mod.HEAPU8.set(bytes, ptr);
        rc = mod._sqlite3_bind_blob(stmtPtr, idx, ptr, bytes.length, SQLITE_TRANSIENT);
        mod._free(ptr);
      } else {
        const str = String(param);
        const len = mod.lengthBytesUTF8(str);
        const ptr = mod._malloc(len + 1);
        mod.stringToUTF8(str, ptr, len + 1);
        rc = mod._sqlite3_bind_text(stmtPtr, idx, ptr, len, SQLITE_TRANSIENT);
        mod._free(ptr);
      }
      if (rc !== SQLITE_OK) {
        throw new Error(`Failed to bind parameter ${idx}: rc=${rc}`);
      }
    }
  }
  getColumnValue(stmtPtr, colIdx) {
    const { mod } = this;
    const type = mod._sqlite3_column_type(stmtPtr, colIdx);
    switch (type) {
      case SQLITE_INTEGER:
        return mod._sqlite3_column_int(stmtPtr, colIdx);
      case SQLITE_FLOAT:
        return mod._sqlite3_column_double(stmtPtr, colIdx);
      case SQLITE_TEXT: {
        const ptr = mod._sqlite3_column_text(stmtPtr, colIdx);
        return ptr ? mod.UTF8ToString(ptr) : null;
      }
      case SQLITE_BLOB: {
        const ptr = mod._sqlite3_column_blob(stmtPtr, colIdx);
        const size = mod._sqlite3_column_bytes(stmtPtr, colIdx);
        if (ptr && size > 0) {
          return new Uint8Array(mod.HEAPU8.buffer, ptr, size).slice();
        }
        return null;
      }
      case SQLITE_NULL:
      default:
        return null;
    }
  }
  export() {
    const { mod, dbPtr } = this;
    const schemaPtr = mod._malloc(5);
    mod.stringToUTF8("main", schemaPtr, 5);
    const pSize = mod._malloc(8);
    mod.setValue(pSize, 0, "i32");
    mod.setValue(pSize + 4, 0, "i32");
    const dataPtr = mod._sqlite3_serialize(dbPtr, schemaPtr, pSize, 0);
    mod._free(schemaPtr);
    if (dataPtr === 0) {
      mod._free(pSize);
      console.log("[CrSqliteDatabase.export] sqlite3_serialize returned null, database may be empty");
      return new Uint8Array(0);
    }
    const sizeLow = mod.getValue(pSize, "i32");
    const sizeHigh = mod.getValue(pSize + 4, "i32");
    mod._free(pSize);
    const size = sizeLow;
    console.log("[CrSqliteDatabase.export] Serialized", size, "bytes");
    if (size <= 0) {
      console.log("[CrSqliteDatabase.export] Invalid size, returning empty");
      mod._free(dataPtr);
      return new Uint8Array(0);
    }
    const result = new Uint8Array(size);
    result.set(new Uint8Array(mod.HEAPU8.buffer, dataPtr, size));
    mod._free(dataPtr);
    return result;
  }
  close() {
    const { mod, dbPtr } = this;
    if (dbPtr) {
      mod._sqlite3_close_v2(dbPtr);
      this.dbPtr = 0;
    }
  }
};
function createSqlJsWrapper(mod) {
  return {
    Database: class Database {
      impl;
      constructor(data) {
        this.impl = new CrSqliteDatabase(mod, data);
      }
      run(sql, params) {
        this.impl.run(sql, params);
      }
      exec(sql) {
        return this.impl.exec(sql);
      }
      export() {
        return this.impl.export();
      }
      close() {
        this.impl.close();
      }
    }
  };
}
var db = null;
var sqlJs = null;
var sqlJsLoadPromise = null;
var currentDbName = null;
var opfsFileHandle = null;
var useOPFS = false;
function checkOPFSSupport() {
  try {
    return typeof navigator !== "undefined" && "storage" in navigator && typeof navigator.storage.getDirectory === "function";
  } catch {
    return false;
  }
}
var hasOPFS = checkOPFSSupport();
console.log("[ProviderWorker] OPFS support:", hasOPFS);
async function loadFromOPFS(dbName) {
  if (!hasOPFS) return null;
  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    try {
      const fileHandle = await root.getFileHandle(fileName, { create: false });
      const file = await fileHandle.getFile();
      if (file.size === 0) {
        console.log("[ProviderWorker] OPFS file exists but is empty");
        return null;
      }
      const buffer = await file.arrayBuffer();
      console.log(`[ProviderWorker] Loaded ${buffer.byteLength} bytes from OPFS`);
      return new Uint8Array(buffer);
    } catch (e) {
      if (e instanceof DOMException && e.name === "NotFoundError") {
        console.log("[ProviderWorker] No existing OPFS file found");
        return null;
      }
      throw e;
    }
  } catch (e) {
    console.error("[ProviderWorker] Error loading from OPFS:", e);
    return null;
  }
}
async function saveToOPFS(dbName, data) {
  if (!hasOPFS) {
    console.log("[ProviderWorker] OPFS not available, skipping save");
    return;
  }
  if (!data || data.byteLength === 0) {
    console.warn("[ProviderWorker] Refusing to save empty database to OPFS");
    return;
  }
  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    const fileHandle = await root.getFileHandle(fileName, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(new Blob([data]));
    await writable.close();
    console.log(`[ProviderWorker] Saved ${data.byteLength} bytes to OPFS`);
  } catch (e) {
    console.error("[ProviderWorker] Error saving to OPFS:", e);
  }
}
async function getOPFSFileHandle(dbName) {
  if (!hasOPFS) return null;
  try {
    const root = await navigator.storage.getDirectory();
    const fileName = `${dbName}.sqlite3`;
    return await root.getFileHandle(fileName, { create: true });
  } catch (e) {
    console.error("[ProviderWorker] Error getting OPFS file handle:", e);
    return null;
  }
}
var requestQueue = [];
var processing = false;
self.onmessage = async (event) => {
  console.log("[ProviderWorker] Received request:", event.data?.type);
  const request = event.data;
  const response = await enqueueRequest(request);
  console.log("[ProviderWorker] Sending response:", response.type);
  self.postMessage(response);
};
async function enqueueRequest(request) {
  return new Promise((resolve) => {
    requestQueue.push({ request, resolve });
    processQueue();
  });
}
async function processQueue() {
  if (processing || requestQueue.length === 0) return;
  processing = true;
  while (requestQueue.length > 0) {
    const { request, resolve } = requestQueue.shift();
    try {
      const result = await handleRequest(request);
      resolve(createResultResponse(request.requestId, result));
    } catch (e) {
      resolve(
        createErrorResponse(
          request.requestId,
          "QUERY_ERROR",
          e instanceof Error ? e.message : String(e)
        )
      );
    }
  }
  processing = false;
}
async function handleRequest(request) {
  switch (request.type) {
    case "open":
      return handleOpen(request.payload.dbName);
    case "close":
      return handleClose();
    case "exec":
      return handleExec(request.payload.sql, request.payload.bind);
    case "query":
      return handleQuery(request.payload.sql, request.payload.bind);
    case "ping":
      return { pong: true, timestamp: Date.now() };
    default:
      throw new Error(`Unknown request type: ${request.type}`);
  }
}
function resolveSiblingUrl(filename) {
  const workerUrl = self.location.href;
  const baseUrl = workerUrl.substring(0, workerUrl.lastIndexOf("/") + 1);
  return baseUrl + filename;
}
async function loadSqlJs() {
  if (sqlJsLoadPromise) return sqlJsLoadPromise;
  sqlJsLoadPromise = (async () => {
    let initFn = self.initCrSqlite;
    if (!initFn) {
      const sqlWasmUrl = resolveSiblingUrl("sql-wasm.js");
      console.log("[ProviderWorker] Loading CR-SQLite WASM from:", sqlWasmUrl);
      const response = await fetch(sqlWasmUrl);
      if (!response.ok) {
        throw new Error(`Failed to fetch sql-wasm.js: ${response.status} ${response.statusText}`);
      }
      const scriptText = await response.text();
      (0, eval)(scriptText);
      initFn = self.initCrSqlite;
    }
    if (!initFn) {
      throw new Error("Failed to load CR-SQLite WASM (initCrSqlite not found)");
    }
    console.log("[ProviderWorker] Initializing CR-SQLite...");
    const mod = await initFn({
      // Locate the .wasm file relative to this worker
      locateFile: (file) => resolveSiblingUrl(file)
    });
    console.log("[ProviderWorker] CR-SQLite module loaded, creating sql.js-compatible wrapper...");
    const sqlJsWrapper = createSqlJsWrapper(mod);
    console.log("[ProviderWorker] CR-SQLite initialized successfully");
    return sqlJsWrapper;
  })();
  return sqlJsLoadPromise;
}
async function handleOpen(dbName) {
  if (!sqlJs) {
    sqlJs = await loadSqlJs();
  }
  if (db && currentDbName === dbName) {
    console.log("[ProviderWorker] Database already open:", dbName);
    return { success: true, persistent: useOPFS };
  }
  if (db) {
    if (useOPFS && currentDbName) {
      try {
        const data = db.export();
        await saveToOPFS(currentDbName, data);
      } catch (e) {
        console.error("[ProviderWorker] Error saving before close:", e);
      }
    }
    db.close();
    db = null;
  }
  currentDbName = dbName;
  useOPFS = false;
  opfsFileHandle = null;
  const existingData = await loadFromOPFS(dbName);
  if (existingData) {
    try {
      db = new sqlJs.Database(existingData);
      useOPFS = true;
      opfsFileHandle = await getOPFSFileHandle(dbName);
      console.log("[ProviderWorker] Database opened from OPFS (persistent)");
      return { success: true, persistent: true };
    } catch (e) {
      console.error("[ProviderWorker] Error opening database from OPFS data:", e);
    }
  }
  db = new sqlJs.Database();
  if (hasOPFS) {
    opfsFileHandle = await getOPFSFileHandle(dbName);
    if (opfsFileHandle) {
      useOPFS = true;
      try {
        const data = db.export();
        await saveToOPFS(dbName, data);
      } catch (e) {
        console.error("[ProviderWorker] Error saving initial database:", e);
        useOPFS = false;
        opfsFileHandle = null;
      }
    }
  }
  console.log(`[ProviderWorker] Database opened (${useOPFS ? "persistent" : "in-memory"})`);
  return { success: true, persistent: useOPFS };
}
async function handleClose() {
  if (db) {
    if (useOPFS && currentDbName) {
      try {
        const data = db.export();
        await saveToOPFS(currentDbName, data);
        console.log("[ProviderWorker] Database saved to OPFS before close");
      } catch (e) {
        console.error("[ProviderWorker] Error saving before close:", e);
      }
    }
    db.close();
    db = null;
  }
  currentDbName = null;
  useOPFS = false;
  opfsFileHandle = null;
  return { success: true };
}
async function handleExec(sql, bind) {
  if (!db) throw new Error("Database not open");
  db.run(sql, bind);
  const sqlUpper = sql.trim().toUpperCase();
  const isWrite = sqlUpper.startsWith("INSERT") || sqlUpper.startsWith("UPDATE") || sqlUpper.startsWith("DELETE") || sqlUpper.startsWith("CREATE") || sqlUpper.startsWith("DROP") || sqlUpper.startsWith("ALTER");
  if (isWrite && useOPFS && currentDbName) {
    try {
      const data = db.export();
      await saveToOPFS(currentDbName, data);
    } catch (e) {
      console.error("[ProviderWorker] Error persisting after exec:", e);
    }
  }
  return { changes: 0 };
}
async function handleQuery(sql, _bind) {
  if (!db) throw new Error("Database not open");
  const results = db.exec(sql);
  if (results.length === 0) return { rows: [] };
  return { rows: results[0].values };
}
export {
  db,
  requestQueue
};
//# sourceMappingURL=provider.js.map
