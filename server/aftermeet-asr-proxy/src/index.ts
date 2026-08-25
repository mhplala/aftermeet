/**
 * AfterMeet ASR Proxy
 *
 * Relays AfterMeet's meeting audio to Volcengine's Doubao streaming ASR
 * (bigmodel_async) over WebSocket, so the real Volcengine API key never ships
 * inside the publicly-distributed AfterMeet.app. Auth mirrors the existing
 * siku-proxy device-token pattern (SikuCloud.deviceToken / X-Siku-App) rather
 * than inventing a new identity system.
 *
 * Routes:
 *   GET /health
 *   GET /v1/transcribe-stream → Volcengine bigmodel_async WebSocket proxy
 */

const volcengineASRWebSocketEndpoint =
  "https://openspeech.bytedance.com/api/v3/sauc/bigmodel_async";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json(
        { service: "aftermeet-asr-proxy", environment: env.ENVIRONMENT, status: "ok" },
        { headers: { "cache-control": "no-store" } }
      );
    }

    if (request.method === "GET" && url.pathname === "/v1/transcribe-stream") {
      try {
        return await handleTranscriptionWebSocket(request, env);
      } catch (error) {
        console.error("[/v1/transcribe-stream] setup failed:", error);
        return jsonError(500, "internal_error");
      }
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleTranscriptionWebSocket(request: Request, env: Env): Promise<Response> {
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return new Response("WebSocket upgrade required", {
      status: 426,
      headers: { upgrade: "websocket", "cache-control": "no-store" },
    });
  }

  // X-Siku-App is a public client identifier, not an authentication secret: it ships in the
  // desktop binary. Real abuse protection must therefore be keyed by data the caller cannot
  // rotate at will (the edge-observed IP) and by an account-wide circuit breaker.
  if (request.headers.get("x-siku-app") !== env.APP_ID) {
    return jsonError(401, "unrecognized_client");
  }

  const deviceToken = bearerToken(request);
  if (!deviceToken || !deviceToken.startsWith("siku-dev-")) {
    return jsonError(401, "missing_device_token");
  }

  const clientIP = request.headers.get("cf-connecting-ip");
  if (!clientIP) {
    return jsonError(400, "missing_client_ip");
  }

  const [deviceLimit, ipLimit, globalLimit] = await Promise.all([
    env.ASR_DEVICE_RATE_LIMITER.limit({ key: deviceToken }),
    env.ASR_IP_RATE_LIMITER.limit({ key: clientIP }),
    env.ASR_GLOBAL_RATE_LIMITER.limit({ key: "aftermeet-asr" }),
  ]);
  if (!deviceLimit.success || !ipLimit.success || !globalLimit.success) {
    return jsonError(429, "rate_limited");
  }

  const upstreamRequestID = crypto.randomUUID();
  const upstreamResponse = await fetch(volcengineASRWebSocketEndpoint, {
    headers: {
      upgrade: "websocket",
      "X-Api-Key": env.VOLCENGINE_API_KEY,
      "X-Api-Resource-Id": env.VOLCENGINE_ASR_RESOURCE_ID,
      "X-Api-Request-Id": upstreamRequestID,
      "X-Api-Connect-Id": upstreamRequestID,
    },
  });

  const upstreamWebSocket = upstreamResponse.webSocket;
  if (upstreamResponse.status !== 101 || !upstreamWebSocket) {
    const upstreamLogID = upstreamResponse.headers.get("x-tt-logid") ?? "missing";
    const upstreamErrorText = (await upstreamResponse.text()).replace(/[\r\n\t]+/g, " ").slice(0, 500);
    console.error("[/v1/transcribe-stream] Volcengine rejected WebSocket upgrade", {
      status: upstreamResponse.status,
      logID: upstreamLogID,
      error: upstreamErrorText,
    });
    return Response.json(
      { error: "transcription_upstream_rejected", upstream_status: upstreamResponse.status, upstream_log_id: upstreamLogID },
      { status: 502, headers: { "cache-control": "no-store" } }
    );
  }

  const webSocketPair = new WebSocketPair();
  const [clientWebSocket, workerWebSocket] = Object.values(webSocketPair);

  // Explicit ArrayBuffer delivery avoids Blob conversion and keeps binary
  // audio frames byte-for-byte intact.
  workerWebSocket.binaryType = "arraybuffer";
  upstreamWebSocket.binaryType = "arraybuffer";
  workerWebSocket.accept({ allowHalfOpen: true });
  upstreamWebSocket.accept({ allowHalfOpen: true });

  relayWebSocketMessages(workerWebSocket, upstreamWebSocket);

  return new Response(null, { status: 101, webSocket: clientWebSocket });
}

function relayWebSocketMessages(clientSideWebSocket: WebSocket, upstreamWebSocket: WebSocket): void {
  let hasStartedClosing = false;

  const closeBothWebSockets = (code = 1011, reason = "proxy_connection_closed") => {
    if (hasStartedClosing) return;
    hasStartedClosing = true;
    for (const webSocket of [clientSideWebSocket, upstreamWebSocket]) {
      if (webSocket.readyState === 0 || webSocket.readyState === 1) {
        try {
          webSocket.close(code, reason);
        } catch {
          // A concurrent close can win between readyState and close().
        }
      }
    }
  };

  clientSideWebSocket.addEventListener("message", (event) => {
    try {
      upstreamWebSocket.send(event.data as ArrayBuffer | string);
    } catch (error) {
      console.error("[transcribe-stream] client→upstream send failed:", error);
      closeBothWebSockets();
    }
  });
  upstreamWebSocket.addEventListener("message", (event) => {
    try {
      clientSideWebSocket.send(event.data as ArrayBuffer | string);
    } catch (error) {
      console.error("[transcribe-stream] upstream→client send failed:", error);
      closeBothWebSockets();
    }
  });

  clientSideWebSocket.addEventListener("close", (event) => closeBothWebSockets(event.code, event.reason));
  upstreamWebSocket.addEventListener("close", (event) => closeBothWebSockets(event.code, event.reason));
  clientSideWebSocket.addEventListener("error", () => closeBothWebSockets());
  upstreamWebSocket.addEventListener("error", () => closeBothWebSockets());
}

function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : null;
}

function jsonError(status: number, error: string): Response {
  return Response.json({ error }, { status, headers: { "cache-control": "no-store" } });
}
