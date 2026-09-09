const secretKey = /authorization|token|apikey|api_key|secret|privateNarration/i;

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        secretKey.test(key) ? "[REDACTED]" : redact(item),
      ]),
    );
  }
  return value;
}

export function logEvent(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  console.log(JSON.stringify({ level: "INFO", event, fields: redact(fields) }));
}

export function logError(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  console.error(JSON.stringify({ level: "ERROR", event, fields: redact(fields) }));
}
