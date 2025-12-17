import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useState, useEffect, useRef, useCallback } from "react";
import "./index.css";

// Types for DbClient (loaded dynamically from /crsql-multitab.js)
interface DbClient {
  ready: Promise<void>;
  isDbProvider: boolean;
  id: string | null;
  open(): Promise<void>;
  exec(sql: string, bind?: unknown[]): Promise<{ rows: unknown[][]; changes: number }>;
  query(sql: string, bind?: unknown[]): Promise<unknown[][]>;
  close(): Promise<void>;
  disconnect(): void;
}

interface Item {
  id: string;
  name: string;
  quantity: number;
}

export function App() {
  const [db, setDb] = useState<DbClient | null>(null);
  const [status, setStatus] = useState<string>("Initializing...");
  const [isProvider, setIsProvider] = useState<boolean>(false);
  const [clientId, setClientId] = useState<string | null>(null);
  const [dbVersion, setDbVersion] = useState<number | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [newItemName, setNewItemName] = useState("");
  const [newItemQty, setNewItemQty] = useState("1");
  const [error, setError] = useState<string | null>(null);
  
  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const refreshData = useCallback(async (dbClient: DbClient) => {
    // Get db_version
    const versionResult = await dbClient.query("SELECT crsql_db_version() as version");
    if (versionResult && versionResult.length > 0 && versionResult[0]) {
      setDbVersion(Number(versionResult[0][0]));
    }

    // Get items
    const itemsResult = await dbClient.query("SELECT id, name, quantity FROM items ORDER BY name");
    const parsedItems: Item[] = (itemsResult || []).map((row: unknown[]) => ({
      id: String(row[0]),
      name: String(row[1]),
      quantity: Number(row[2]),
    }));
    setItems(parsedItems);
  }, []);

  // Initialize database
  useEffect(() => {
    let mounted = true;
    let dbClient: DbClient | null = null;

    async function init() {
      try {
        setStatus("Loading CR-SQLite...");
        
        // Dynamically import the DbClient from the served file
        // @ts-expect-error - Dynamic import of served JS file
        const module = await import("/crsql-multitab.js");
        const { DbClient: DbClientClass } = module;

        setStatus("Connecting to SharedWorker...");
        dbClient = new DbClientClass({
          dbName: "scratchpad-demo",
          coordinatorUrl: "/coordinator.js",
          providerWorkerUrl: "/provider.js",
        }) as DbClient;

        await dbClient.ready;
        
        if (!mounted) return;

        setDb(dbClient);
        setIsProvider(dbClient.isDbProvider);
        setClientId(dbClient.id);
        setStatus("Opening database...");

        await dbClient.open();
        
        if (!mounted) return;

        // Create CRR table if needed
        await dbClient.exec(`
          CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            quantity INTEGER DEFAULT 0
          )
        `);
        
        // Make it a CRR (conflict-free replicated relation)
        // Note: This is idempotent, safe to call multiple times
        try {
          await dbClient.exec("SELECT crsql_as_crr('items')");
        } catch {
          // Table might already be a CRR
        }

        setStatus("Connected!");
        setError(null);
        
        // Initial load
        await refreshData(dbClient);

      } catch (e) {
        if (!mounted) return;
        const msg = e instanceof Error ? e.message : String(e);
        setError(msg);
        setStatus("Error");
        console.error("Init error:", e);
      }
    }

    init();

    return () => {
      mounted = false;
      if (dbClient) {
        dbClient.disconnect();
      }
    };
  }, [refreshData]);

  // Poll for updates (simple approach for cross-tab visibility)
  useEffect(() => {
    if (!db) return;

    const currentDb = db;
    pollIntervalRef.current = setInterval(async () => {
      try {
        await refreshData(currentDb);
      } catch (e) {
        console.error("Poll error:", e);
      }
    }, 1000); // Poll every second

    return () => {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }
    };
  }, [db, refreshData]);

  const addItem = async () => {
    if (!db || !newItemName.trim()) return;
    
    try {
      const id = crypto.randomUUID();
      const qty = parseInt(newItemQty) || 1;
      await db.exec(
        "INSERT INTO items (id, name, quantity) VALUES (?, ?, ?)",
        [id, newItemName.trim(), qty]
      );
      setNewItemName("");
      setNewItemQty("1");
      await refreshData(db);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
    }
  };

  const updateQuantity = async (id: string, delta: number) => {
    if (!db) return;
    
    try {
      await db.exec(
        "UPDATE items SET quantity = quantity + ? WHERE id = ?",
        [delta, id]
      );
      await refreshData(db);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
    }
  };

  const deleteItem = async (id: string) => {
    if (!db) return;
    
    try {
      await db.exec("DELETE FROM items WHERE id = ?", [id]);
      await refreshData(db);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setError(msg);
    }
  };

  return (
    <div className="container mx-auto p-8 max-w-2xl">
      <Card className="mb-6">
        <CardHeader>
          <CardTitle className="text-2xl">CR-SQLite Browser Demo</CardTitle>
          <CardDescription>
            Multi-tab CRDT database with SharedWorker coordination
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <span className="font-medium">Status:</span>{" "}
              <span className={status === "Connected!" ? "text-green-600" : status === "Error" ? "text-red-600" : "text-yellow-600"}>
                {status}
              </span>
            </div>
            <div>
              <span className="font-medium">Role:</span>{" "}
              <span className={isProvider ? "text-blue-600 font-bold" : ""}>
                {isProvider ? "Provider (owns DB)" : "Client (proxied)"}
              </span>
            </div>
            <div>
              <span className="font-medium">Client ID:</span>{" "}
              <span className="font-mono text-xs">{clientId?.slice(0, 8) || "..."}</span>
            </div>
            <div>
              <span className="font-medium">DB Version:</span>{" "}
              <span className="font-mono font-bold text-lg">{dbVersion ?? "..."}</span>
            </div>
          </div>
          
          {error && (
            <div className="mt-4 p-3 bg-red-100 text-red-700 rounded text-sm">
              {error}
            </div>
          )}

          <div className="mt-4 p-3 bg-blue-50 text-blue-800 rounded text-sm">
            Open this page in another tab to test cross-tab sync!
            <br />
            Changes made here will appear in other tabs (polling every 1s).
          </div>
        </CardContent>
      </Card>

      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Add Item</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <div className="flex-1">
              <Label htmlFor="name" className="sr-only">Name</Label>
              <Input
                id="name"
                placeholder="Item name"
                value={newItemName}
                onChange={(e) => setNewItemName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && addItem()}
              />
            </div>
            <div className="w-20">
              <Label htmlFor="qty" className="sr-only">Quantity</Label>
              <Input
                id="qty"
                type="number"
                min="1"
                value={newItemQty}
                onChange={(e) => setNewItemQty(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && addItem()}
              />
            </div>
            <Button onClick={addItem} disabled={!db || !newItemName.trim()}>
              Add
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Items ({items.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {items.length === 0 ? (
            <p className="text-gray-500 text-center py-4">No items yet. Add one above!</p>
          ) : (
            <ul className="divide-y">
              {items.map((item) => (
                <li key={item.id} className="py-3 flex items-center justify-between">
                  <span className="font-medium">{item.name}</span>
                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => updateQuantity(item.id, -1)}
                      disabled={!db}
                    >
                      -
                    </Button>
                    <span className="w-8 text-center font-mono">{item.quantity}</span>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => updateQuantity(item.id, 1)}
                      disabled={!db}
                    >
                      +
                    </Button>
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => deleteItem(item.id)}
                      disabled={!db}
                    >
                      Delete
                    </Button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

export default App;
