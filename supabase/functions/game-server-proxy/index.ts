import NodeWebSocket from "npm:ws@8.18.3";

const upstreamOrigin = Deno.env.get("GAME_SERVER_UPSTREAM_URL");
if (!upstreamOrigin || new URL(upstreamOrigin).protocol !== "https:") {
  throw new Error("Set GAME_SERVER_UPSTREAM_URL to your HTTPS Worker origin.");
}
const functionName = "game-server-proxy";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization,content-type,x-client-version,apikey",
  "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
  "access-control-max-age": "86400",
};

function requestRoute(url: URL): { upstreamPath: string; publicPrefix: string } {
  const marker = `/${functionName}`;
  const markerIndex = url.pathname.indexOf(marker);
  const suffix = markerIndex < 0
    ? url.pathname
    : url.pathname.slice(markerIndex + marker.length);
  const upstreamPath = suffix && suffix !== "/" ? suffix : "/health";
  // The Supabase gateway strips `/functions/v1` before the request reaches
  // the isolate, so never derive the public WebSocket path from url.pathname.
  const publicOrigin = (Deno.env.get("SUPABASE_URL") ?? url.origin)
    .replace(/\/$/, "");
  return {
    upstreamPath,
    publicPrefix: `${publicOrigin}/functions/v1/${functionName}`,
  };
}

function upstreamUrl(requestUrl: URL, path: string, webSocket = false): URL {
  const target = new URL(upstreamOrigin);
  target.protocol = webSocket ? "wss:" : "https:";
  target.pathname = path;
  target.search = requestUrl.search;
  return target;
}

function upstreamHeaders(request: Request): Headers {
  const headers = new Headers(request.headers);
  for (const name of [
    "host",
    "content-length",
    "connection",
    "upgrade",
    "sec-websocket-key",
    "sec-websocket-version",
    "sec-websocket-extensions",
  ]) headers.delete(name);
  return headers;
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(corsHeaders)) {
    headers.set(name, value);
  }
  headers.delete("content-length");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function proxyHttp(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const { upstreamPath, publicPrefix } = requestRoute(url);
  const target = upstreamUrl(url, upstreamPath);
  const response = await fetch(target, {
    method: request.method,
    headers: upstreamHeaders(request),
    body: request.method === "GET" || request.method === "HEAD"
      ? undefined
      : request.body,
    redirect: "manual",
  });

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) return withCors(response);

  const text = await response.text();
  let body = text;
  try {
    const json = JSON.parse(text) as Record<string, unknown>;
    if (typeof json.socketUrl === "string") {
      const socket = new URL(json.socketUrl);
      const proxy = new URL(publicPrefix);
      proxy.protocol = "wss:";
      proxy.pathname = `${proxy.pathname.replace(/\/$/, "")}${socket.pathname}`;
      proxy.search = socket.search;
      json.socketUrl = proxy.toString();
      body = JSON.stringify(json);
    }
  } catch {
    // Preserve an upstream response that only advertises JSON but is not JSON.
  }

  const headers = new Headers(response.headers);
  headers.delete("content-length");
  return withCors(new Response(body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  }));
}

function proxyWebSocket(request: Request): Response {
  const url = new URL(request.url);
  const { upstreamPath } = requestRoute(url);
  const target = upstreamUrl(url, upstreamPath, true);
  const authorization = request.headers.get("authorization");
  const { socket: client, response } = Deno.upgradeWebSocket(request);
  const pending: Array<string | ArrayBuffer | Uint8Array> = [];

  const upstream = new NodeWebSocket(target.toString(), {
    headers: authorization ? { Authorization: authorization } : undefined,
  });

  const finished = new Promise<void>((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      resolve();
    };

    client.addEventListener("message", (event) => {
      const data = event.data as string | ArrayBuffer | Uint8Array;
      if (upstream.readyState === NodeWebSocket.OPEN) upstream.send(data);
      else if (upstream.readyState === NodeWebSocket.CONNECTING) pending.push(data);
    });
    client.addEventListener("close", () => {
      if (upstream.readyState === NodeWebSocket.OPEN ||
          upstream.readyState === NodeWebSocket.CONNECTING) upstream.close();
      finish();
    });
    client.addEventListener("error", () => {
      if (upstream.readyState === NodeWebSocket.OPEN ||
          upstream.readyState === NodeWebSocket.CONNECTING) upstream.close();
      finish();
    });

    upstream.on("open", () => {
      for (const data of pending.splice(0)) upstream.send(data);
    });
    upstream.on("message", (data, isBinary) => {
      if (client.readyState !== WebSocket.OPEN) return;
      client.send(isBinary ? new Uint8Array(data as Uint8Array) : data.toString());
    });
    upstream.on("close", (code, reason) => {
      if (client.readyState === WebSocket.OPEN) {
        client.close(code || 1011, reason.toString().slice(0, 120));
      }
      finish();
    });
    upstream.on("error", () => {
      if (client.readyState === WebSocket.OPEN) {
        client.close(1011, "upstream_connection_failed");
      }
      finish();
    });
  });

  EdgeRuntime.waitUntil(finished);
  return response;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if ((request.headers.get("upgrade") ?? "").toLowerCase() === "websocket") {
    return proxyWebSocket(request);
  }
  try {
    return await proxyHttp(request);
  } catch (error) {
    return withCors(Response.json({
      error: {
        code: "UPSTREAM_UNAVAILABLE",
        message: "公网游戏服务暂时不可达，请稍后重试",
        detail: error instanceof Error ? error.message : String(error),
      },
    }, { status: 502 }));
  }
});
