import { createRemoteJWKSet, jwtVerify } from "jose";
import type { Env } from "../env";
import { ServerError } from "../utils/errors";

export interface AuthenticatedUser { id: string; email?: string | undefined; accessToken: string }

const jwks = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

export async function authenticate(request: Request, env: Env): Promise<AuthenticatedUser> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new ServerError("AUTH_REQUIRED", "请先登录后再使用公网联机", 401);
  const accessToken = match[1]!;
  if (accessToken.length > 8192) throw new ServerError('INVALID_TOKEN', '登录凭证格式错误', 401);
  const base = env.SUPABASE_URL.replace(/\/$/, "");
  try {
    let keySet = jwks.get(base);
    if (!keySet) { keySet = createRemoteJWKSet(new URL(`${base}/auth/v1/.well-known/jwks.json`)); jwks.set(base, keySet); }
    const verified = await jwtVerify(accessToken, keySet, { audience: "authenticated", issuer: `${base}/auth/v1`, requiredClaims: ['sub', 'exp', 'role'] });
    if (!verified.payload.sub || verified.payload.role !== 'authenticated' || !/^[0-9a-f-]{36}$/i.test(verified.payload.sub)) throw new Error("invalid user claims");
    return { id: verified.payload.sub, email: typeof verified.payload.email === "string" ? verified.payload.email : undefined, accessToken };
  } catch {
    // Supabase projects using the legacy symmetric signing secret cannot expose a public verification key.
    const response = await fetch(`${base}/auth/v1/user`, { signal: AbortSignal.timeout(10_000), headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${accessToken}` } });
    if (!response.ok) throw new ServerError("INVALID_TOKEN", "登录凭证无效或已过期", 401);
    const user = await response.json<{ id?: string; email?: string }>();
    if (!user.id || !/^[0-9a-f-]{36}$/i.test(user.id)) throw new ServerError("INVALID_TOKEN", "登录凭证缺少用户标识", 401);
    return { id: user.id, email: user.email, accessToken };
  }
}
