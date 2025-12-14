// src/coordinator/shared-worker.ts
var clients = /* @__PURE__ */ new Map();
var currentProviderId = null;
var pendingRequests = [];
self.onconnect = (event) => {
  console.log("[SharedWorker] New connection received");
  const port = event.ports[0];
  const clientId = crypto.randomUUID();
  const connection = {
    port,
    clientId,
    isProvider: false
  };
  clients.set(clientId, connection);
  console.log("[SharedWorker] Client registered:", clientId, "Total clients:", clients.size);
  port.onmessage = (msg) => {
    console.log("[SharedWorker] Message from client", clientId, ":", msg.data?.type || msg.data);
    handleClientMessage(clientId, msg.data);
  };
  port.onmessageerror = () => handleClientDisconnect(clientId);
  port.start();
  const connectedMsg = { type: "connected", clientId };
  port.postMessage(connectedMsg);
  console.log("[SharedWorker] Sent connected message to", clientId);
  tryBecomeProvider(clientId);
};
function tryBecomeProvider(clientId) {
  const client = clients.get(clientId);
  if (!client) return;
  if (currentProviderId) {
    console.log("[SharedWorker] Provider already exists, notifying new client:", clientId);
    const notification = {
      type: "provider-elected",
      providerId: currentProviderId,
      isYou: false
    };
    client.port.postMessage(notification);
    return;
  }
  console.log("[SharedWorker] Telling client to try becoming provider:", clientId);
  client.port.postMessage({ type: "try-become-provider" });
}
function electProvider(clientId) {
  const client = clients.get(clientId);
  if (!client) return;
  currentProviderId = clientId;
  client.isProvider = true;
  console.log("[SharedWorker] Provider elected:", clientId);
  for (const [id, conn] of clients) {
    const notification = {
      type: "provider-elected",
      providerId: clientId,
      isYou: id === clientId
    };
    conn.port.postMessage(notification);
  }
  processPendingRequests();
}
function processPendingRequests() {
  while (pendingRequests.length > 0) {
    const pending = pendingRequests.shift();
    if (pending) {
      forwardRequestToProvider(pending.clientId, pending.request);
    }
  }
}
function handleClientMessage(clientId, msg) {
  if ("type" in msg && msg.type === "disconnect") {
    console.log("[SharedWorker] Received disconnect message from", clientId);
    handleClientDisconnect(clientId);
    return;
  }
  if ("type" in msg && msg.type === "became-provider") {
    console.log("[SharedWorker] Client became provider:", clientId);
    electProvider(clientId);
    return;
  }
  if ("type" in msg && msg.type === "forward-response") {
    handleProviderResponse(msg);
    return;
  }
  const request = msg;
  if (!currentProviderId) {
    pendingRequests.push({ clientId, request });
    return;
  }
  if (clientId === currentProviderId) {
    console.warn("[SharedWorker] Provider sent request to itself, ignoring");
    return;
  }
  forwardRequestToProvider(clientId, request);
}
function forwardRequestToProvider(clientId, request) {
  if (!currentProviderId) {
    sendNoProviderError(clientId, request.requestId);
    return;
  }
  const provider = clients.get(currentProviderId);
  if (!provider) {
    sendNoProviderError(clientId, request.requestId);
    return;
  }
  const forwardMsg = {
    type: "forward-request",
    clientId,
    request
  };
  provider.port.postMessage(forwardMsg);
}
function handleProviderResponse(msg) {
  const client = clients.get(msg.clientId);
  if (!client) {
    console.warn("[SharedWorker] Response for unknown client:", msg.clientId);
    return;
  }
  client.port.postMessage(msg.response);
}
function sendNoProviderError(clientId, requestId) {
  const client = clients.get(clientId);
  if (!client) return;
  const error = {
    type: "error",
    requestId,
    payload: {
      code: "NO_PROVIDER",
      message: "No database provider available"
    }
  };
  client.port.postMessage(error);
}
function handleClientDisconnect(clientId) {
  const client = clients.get(clientId);
  if (!client) return;
  console.log("[SharedWorker] Client disconnected:", clientId);
  const wasProvider = client.isProvider;
  clients.delete(clientId);
  if (wasProvider) {
    currentProviderId = null;
    console.log("[SharedWorker] Provider disconnected, triggering failover");
    for (const [id] of clients) {
      tryBecomeProvider(id);
      break;
    }
  }
}
export {
  clients,
  currentProviderId,
  handleClientDisconnect
};
//# sourceMappingURL=coordinator.js.map
