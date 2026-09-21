import fs from "node:fs";
import http from "node:http";
import https from "node:https";

const captures = [];
let nextCaptureId = 1;

function sendJson(response, status, value) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(value));
}

function collectBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function captureForRequest(request, url, body) {
  const form = Object.fromEntries(new URLSearchParams(body));
  const capture = {
    id: nextCaptureId++,
    method: request.method,
    path: `${url.pathname}${url.search}`,
    headers: request.headers,
    form,
    receivedAt: Date.now(),
  };
  captures.push(capture);
  return capture;
}

async function handle(request, response) {
  const url = new URL(request.url, "http://token-exchange-mock");

  if (request.method === "GET" && url.pathname === "/health") {
    return sendJson(response, 200, { status: "ok" });
  }

  if (request.method === "DELETE" && url.pathname === "/captures") {
    captures.length = 0;
    return sendJson(response, 200, { status: "reset" });
  }

  if (request.method === "GET" && url.pathname.startsWith("/captures/")) {
    const clientId = decodeURIComponent(url.pathname.slice("/captures/".length));
    return sendJson(response, 200, {
      captures: captures.filter((capture) => capture.form.client_id === clientId),
    });
  }

  if (request.method !== "POST" || !url.pathname.startsWith("/token/")) {
    return sendJson(response, 404, { error: "not found" });
  }

  const body = await collectBody(request);
  captureForRequest(request, url, body);
  const mode = url.pathname.slice("/token/".length);
  const delayMs = Number(url.searchParams.get("delay_ms") ?? "0");
  if (delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
  }

  if (response.destroyed) {
    return;
  }

  switch (mode) {
    case "success": {
      const payload = {
        access_token: url.searchParams.get("access_token") ?? "exchanged-token",
      };
      if (url.searchParams.get("additional") === "true") {
        payload.token_type = "Bearer";
        payload.expires_in = 300;
        payload.scope = "read write";
      }
      return sendJson(response, 200, payload);
    }
    case "missing":
      return sendJson(response, 200, { token_type: "Bearer" });
    case "empty":
      return sendJson(response, 200, { access_token: "" });
    case "nonstring":
      return sendJson(response, 200, { access_token: 42 });
    case "invalid-json":
      response.writeHead(200, { "content-type": "application/json" });
      return response.end("{not-json");
    case "error-json":
      return sendJson(response, Number(url.searchParams.get("status") ?? "401"), {
        error: "invalid_subject_token",
        error_description: "details must not cross the plugin boundary",
      });
    case "error-text":
      response.writeHead(Number(url.searchParams.get("status") ?? "503"), {
        "content-type": "text/plain",
      });
      return response.end("token endpoint unavailable");
    default:
      return sendJson(response, 404, { error: "unknown mode" });
  }
}

const httpServer = http.createServer((request, response) => {
  handle(request, response).catch((error) => {
    sendJson(response, 500, { error: error.message });
  });
});

httpServer.listen(8080, "0.0.0.0");

const httpsServer = https.createServer(
  {
    key: fs.readFileSync(new URL("./tls-key.pem", import.meta.url)),
    cert: fs.readFileSync(new URL("./tls-cert.pem", import.meta.url)),
  },
  (request, response) => {
    handle(request, response).catch((error) => {
      sendJson(response, 500, { error: error.message });
    });
  }
);

httpsServer.listen(8443, "0.0.0.0");
