import "dotenv/config";
import app from "./app";
import { connectMongo } from "./db/mongo";
import { log } from "./utils/logger";

const PORT = Number(process.env.PORT) || 5002;

(async () => {
  await connectMongo();
  
  const server = app.listen(PORT, () => {
    log.server(`Running on http://localhost:${PORT}`);
  });

  server.on("error", (err: any) => {
    if (err && err.code === "EADDRINUSE") {
      log.error(`Port ${PORT} is already in use`);
      process.exit(1);
    }
    log.error("Server error:", err.message || err);
    process.exit(1);
  });
})().catch((err) => {
  log.error("Startup failed:", err.message || err);
  process.exit(1);
});
