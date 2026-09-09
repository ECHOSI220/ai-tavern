import { ZodError } from 'zod';

export class ServerError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 400,
    readonly recoverable = false,
    readonly detailsSafe?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "ServerError";
  }
}

export function errorResponse(error: unknown, requestId: string): Response {
  const safe = error instanceof ZodError ? new ServerError('INVALID_INPUT', '请求字段缺失或格式不正确', 400, true) : error;
  const known = safe instanceof ServerError;
  const status = known ? safe.status : 500;
  const body = {
    error: {
      code: known ? safe.code : "INTERNAL_ERROR",
      message: known ? safe.message : "服务器暂时无法处理请求",
      requestId,
      recoverable: known ? safe.recoverable : false,
      ...(known && safe.detailsSafe ? { detailsSafe: safe.detailsSafe } : {}),
    },
  };
  return Response.json(body, { status });
}

export function requireString(
  value: unknown,
  field: string,
  maxLength = 256,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new ServerError("INVALID_INPUT", `${field}不能为空`, 400, true);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new ServerError("INVALID_INPUT", `${field}过长`, 400, true);
  }
  return normalized;
}
