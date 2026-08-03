"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const morgan_1 = __importDefault(require("morgan"));
const compression_1 = __importDefault(require("compression"));
const search_1 = __importDefault(require("./routes/search"));
const album_1 = __importDefault(require("./routes/album"));
const artist_1 = __importDefault(require("./routes/artist"));
const track_1 = __importDefault(require("./routes/track"));
const system_1 = __importDefault(require("./routes/system"));
const email_1 = __importDefault(require("./routes/email"));
const auth_1 = __importDefault(require("./routes/auth"));
const sync_1 = __importDefault(require("./routes/sync"));
const recommendations_1 = __importDefault(require("./routes/recommendations"));
const config_1 = __importDefault(require("./routes/config"));
const app = (0, express_1.default)();
// Core middleware
app.use((0, cors_1.default)());
app.use(express_1.default.json({ limit: "10mb" })); // Increased for sync data
app.use((0, morgan_1.default)("tiny"));
app.use((0, compression_1.default)());
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
app.use("/v1/search", search_1.default);
app.use("/v1/album", album_1.default);
app.use("/v1/artist", artist_1.default);
app.use("/v1/track", track_1.default);
app.use("/v1/system", system_1.default);
app.use("/v1/email", email_1.default);
app.use("/v1/auth", auth_1.default);
app.use("/v1/sync", sync_1.default);
app.use("/v1/recommendations", recommendations_1.default);
app.use("/v1/config", config_1.default);
// 404
app.use((_req, res) => {
    res.status(404).json({ error: "Not Found" });
});
// Error handler (kept tiny; no stack leak in prod)
app.use(
// eslint-disable-next-line @typescript-eslint/no-unused-vars
(err, _req, res, _next) => {
    const code = err.status || 500;
    const msg = process.env.NODE_ENV === "production"
        ? "Internal Server Error"
        : err.message || "Internal Server Error";
    res.status(code).json({ error: msg });
});
exports.default = app;
//# sourceMappingURL=app.js.map