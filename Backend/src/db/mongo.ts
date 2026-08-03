import mongoose from "mongoose";
import { log } from "../utils/logger";

export async function connectMongo(uri?: string) {
  const mongoUri = uri ?? process.env.MONGODB_URI ?? "mongodb://localhost:27017/openmusic";
  if (!mongoUri) throw new Error("MONGODB_URI missing in env");

  mongoose.set("strictQuery", true);

  await mongoose.connect(mongoUri);
  log.db("Connected successfully");

  // Connection error handling
  mongoose.connection.on("error", (err) => {
    log.error("Database connection error:", err.message);
  });

  return mongoose.connection;
}