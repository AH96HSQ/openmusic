"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const app_1 = __importDefault(require("./app"));
const mongo_1 = require("./db/mongo");
const logger_1 = require("./utils/logger");
const PORT = Number(process.env.PORT) || 5002;
(async () => {
    await (0, mongo_1.connectMongo)();
    const server = app_1.default.listen(PORT, () => {
        logger_1.log.server(`Running on http://localhost:${PORT}`);
    });
    server.on("error", (err) => {
        if (err && err.code === "EADDRINUSE") {
            logger_1.log.error(`Port ${PORT} is already in use`);
            process.exit(1);
        }
        logger_1.log.error("Server error:", err.message || err);
        process.exit(1);
    });
})().catch((err) => {
    logger_1.log.error("Startup failed:", err.message || err);
    process.exit(1);
});
//# sourceMappingURL=server.js.map