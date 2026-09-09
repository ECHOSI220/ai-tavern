import { ServerError } from "./errors";

const windows = new Map<string, number[]>();
export function enforceRateLimit(key: string, limit = 60, periodMs = 60_000): void {
  const timestamp = Date.now();
  const values = (windows.get(key) ?? []).filter((item) => item > timestamp - periodMs);
  if (values.length >= limit) throw new ServerError("RATE_LIMITED", "请求过于频繁，请稍后重试", 429);
  values.push(timestamp); windows.set(key, values);
  if (windows.size > 10_000) for (const [id, list] of windows) if (list.at(-1)! < timestamp - periodMs) windows.delete(id);
}
