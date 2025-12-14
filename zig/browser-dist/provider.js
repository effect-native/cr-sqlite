// src/shared/rpc-types.ts
function createResultResponse(requestId, result) {
  return { type: "result", requestId, payload: { result } };
}
function createErrorResponse(requestId, code, message) {
  return { type: "error", requestId, payload: { code, message } };
}

// src/provider/worker.ts
console.log("[ProviderWorker] Starting...");
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
  if (!hasOPFS) return;
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
async function loadSqlJs() {
  if (sqlJsLoadPromise) return sqlJsLoadPromise;
  sqlJsLoadPromise = (async () => {
    let initFn = self.initSqlJs;
    if (!initFn) {
      console.log("[ProviderWorker] Loading sql.js via fetch + eval...");
      const response = await fetch(
        "https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/sql-wasm.js"
      );
      const scriptText = await response.text();
      (0, eval)(scriptText);
      initFn = self.initSqlJs;
    }
    if (!initFn) {
      throw new Error("Failed to load sql.js");
    }
    console.log("[ProviderWorker] Initializing sql.js...");
    const sql = await initFn({
      locateFile: (file) => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.10.3/${file}`
    });
    console.log("[ProviderWorker] sql.js initialized successfully");
    return sql;
  })();
  return sqlJsLoadPromise;
}
async function handleOpen(dbName) {
  if (!sqlJs) {
    sqlJs = await loadSqlJs();
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
