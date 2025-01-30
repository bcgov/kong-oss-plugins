import { APIRequestContext, expect } from "@playwright/test";

let requestBody: any = {};
let headers: Record<string, string> = {
  Accept: "application/json",
  "Content-Type": "application/json",
};

export function setRequestBody(body: any) {
  requestBody = body;
}

export function setHeaders(newHeaders: Record<string, string>) {
  headers = { ...headers, ...newHeaders };
}

export async function callAPI(
  request: APIRequestContext,
  endpoint: string,
  method: string
) {
  const options: any = {
    method,
    headers,
  };

  if (method.toUpperCase() === "PUT" || method.toUpperCase() === "POST") {
    options.data = JSON.stringify(requestBody);
  }

  const response = await request.fetch(endpoint, options);

  //expect(response.status()).toBeLessThan(300);

  let responseBody: any;
  try {
    responseBody = await response.json();
  } catch (e) {
    responseBody = null;
  }

  if (response.status() >= 300) {
    const errors = await response.text();
    console.error("failed to call", endpoint, method, errors);
    throw new Error("failed to call " + endpoint);
  }

  return {
    apiRes: {
      status: response.status(),
      body: responseBody,
      headers: response.headers(),
    },
  };
}
