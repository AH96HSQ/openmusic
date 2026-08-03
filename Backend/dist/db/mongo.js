"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.connectMongo = connectMongo;
const mongoose_1 = __importDefault(require("mongoose"));
const logger_1 = require("../utils/logger");
async function connectMongo(uri) {
    const mongoUri = uri ?? process.env.MONGODB_URI ?? "mongodb://localhost:27017/openmusic";
    if (!mongoUri)
        throw new Error("MONGODB_URI missing in env");
    mongoose_1.default.set("strictQuery", true);
    await mongoose_1.default.connect(mongoUri);
    logger_1.log.db("Connected successfully");
    // Connection error handling
    mongoose_1.default.connection.on("error", (err) => {
        logger_1.log.error("Database connection error:", err.message);
    });
    return mongoose_1.default.connection;
}
//# sourceMappingURL=mongo.js.map