import express from "express";
import cors from "cors";
import morgan from "morgan";
import compression from "compression";
import searchRouter from "./routes/search";
import albumRouter from "./routes/album";
import artistRouter from "./routes/artist";
import trackRouter from "./routes/track";
import systemRouter from "./routes/system";
import emailRouter from "./routes/email";
import authRouter from "./routes/auth";
import syncRouter from "./routes/sync";
import recommendationsRouter from "./routes/recommendations";
import configRouter from "./routes/config";

const app = express();

// Core middleware
app.use(cors());
app.use(express.json({ limit: "10mb" })); // Increased for sync data
app.use(morgan("tiny"));
app.use(compression());

// Healthcheck
app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    uptime: process.uptime(),
    env: {
      node: process.version,
      port: process.env.PORT ?? "unset",
    },
  });
});

// v1 routes
app.use("/v1/search", searchRouter);
app.use("/v1/album", albumRouter);
app.use("/v1/artist", artistRouter);
app.use("/v1/track", trackRouter);
app.use("/v1/system", systemRouter);
app.use("/v1/email", emailRouter);
app.use("/v1/auth", authRouter);
app.use("/v1/sync", syncRouter);
app.use("/v1/recommendations", recommendationsRouter);
app.use("/v1/config", configRouter);

// 404
app.use((_req, res) => {
  res.status(404).json({ error: "Not Found" });
});

// Error handler (kept tiny; no stack leak in prod)
app.use(
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  (err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    const code = err.status || 500;
    const msg =
      process.env.NODE_ENV === "production"
        ? "Internal Server Error"
        : err.message || "Internal Server Error";
    res.status(code).json({ error: msg });
  }
);

export default app;
