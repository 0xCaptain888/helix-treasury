import pino from "pino";
import type { Config } from "./config.js";

export function createLogger(_config: Config): pino.Logger {
  const isDev = process.env.NODE_ENV !== "production";
  return pino({
    level: process.env.LOG_LEVEL ?? "info",
    transport: isDev ? { target: "pino-pretty", options: { colorize: true } } : undefined,
  });
}
