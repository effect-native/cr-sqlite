// src/shared/rpc-types.ts
function createResultResponse(requestId, result) {
  return { type: "result", requestId, payload: { result } };
}
function createErrorResponse(requestId, code, message) {
  return { type: "error", requestId, payload: { code, message } };
}

// src/provider/worker.ts
var db = null;
var sqlJs = null;
var requestQueue = [];
var processing = false;
self.onmessage = async (event) => {
  const request = event.data;
  const response = await enqueueRequest(request);
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
async function handleOpen(_dbName) {
  if (!sqlJs) {
    const initSqlJs = self.initSqlJs;
    if (!initSqlJs) {
      throw new Error("sql.js not loaded");
    }
    sqlJs = await initSqlJs();
  }
  if (db) {
    db.close();
  }
  db = new sqlJs.Database();
  return { success: true };
}
async function handleClose() {
  if (db) {
    db.close();
    db = null;
  }
  return { success: true };
}
async function handleExec(sql, bind) {
  if (!db) throw new Error("Database not open");
  db.run(sql, bind);
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
