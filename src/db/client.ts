import "server-only";

import { neonConfig, Pool } from "@neondatabase/serverless";
import { attachDatabasePool } from "@vercel/functions";
import { drizzle } from "drizzle-orm/neon-serverless";
import WebSocket from "ws";

import { env } from "@/server/env";

import * as schema from "./schema";

let database: ReturnType<typeof createDatabase> | undefined;

function createDatabase() {
  neonConfig.webSocketConstructor = WebSocket;
  const pool = new Pool({
    connectionString: env.database().DATABASE_URL,
    idleTimeoutMillis: 5_000,
    max: 5,
  });
  pool.on("error", (error: Error) => console.error("Unexpected Neon pool error", error.message));
  attachDatabasePool(pool);
  return drizzle({ client: pool, schema });
}

export function getDb() {
  database ??= createDatabase();
  return database;
}
