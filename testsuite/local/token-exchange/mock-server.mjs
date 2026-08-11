import http from "node:http";

const captures = new Map();

function json(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

const server = http.createServer((request, response) => {
  const url = new URL(request.url, "http://token-exchange-mock");

  if (request.method === "GET" && url.pathname === "/health") {
    return json(response, 200, { status: "ok" });
  }

  if (request.method === "GET" && url.pathname.startsWith("/captures/")) {
    const id = decodeURIComponent(url.pathname.slice("/captures/".length));
    if (!captures.has(id)) {
      return json(response, 404, { message: "capture not found" });
    }
    return json(response, 200, captures.get(id));
  }

  if (request.method === "DELETE" && url.pathname === "/captures") {
    captures.clear();
    response.writeHead(204);
    return response.end();
  }

  if (request.method !== "POST" || url.pathname !== "/token") {
    return json(response, 404, { message: "not found" });
  }

  const chunks = [];
  request.on("data", (chunk) => chunks.push(chunk));
  request.on("end", () => {
    const rawBody = Buffer.concat(chunks).toString("utf8");
    const form = Object.fromEntries(new URLSearchParams(rawBody));
    const capture = url.searchParams.get("capture");
    if (capture) {
      captures.set(capture, {
        method: request.method,
        headers: request.headers,
        rawBody,
        form,
      });
    }

    const mode = url.searchParams.get("mode") ?? "success";
    if (mode === "invalid-json") {
      response.writeHead(200, { "content-type": "application/json" });
      return response.end("{not-json");
    }
    if (mode === "non-200-json") {
      return json(response, 401, { error: "invalid_grant", detail: "must not leak" });
    }
    if (mode === "non-200-text") {
      response.writeHead(503, { "content-type": "text/plain" });
      return response.end("temporarily unavailable");
    }
    if (mode === "missing") {
      return json(response, 200, { token_type: "Bearer" });
    }
    if (mode === "non-string") {
      return json(response, 200, { access_token: 12345 });
    }
    if (mode === "empty") {
      return json(response, 200, { access_token: "" });
    }

    const body = { access_token: url.searchParams.get("access_token") ?? "exchanged-token" };
    if (mode === "success-extra") {
      Object.assign(body, {
        token_type: "Bearer",
        expires_in: 300,
        scope: "read write",
      });
    }
    return json(response, 200, body);
  });
});

server.listen(8080, "0.0.0.0");
