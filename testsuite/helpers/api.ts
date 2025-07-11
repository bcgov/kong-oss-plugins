import { APIRequestContext, APIResponse, expect } from "@playwright/test";
import logger from "./logger";
import { Serializable } from "worker_threads";

let requestBody: any = {};
let headers: Record<string, string> = {
  Accept: "application/json",
  "Content-Type": "application/json",
  Connection: "close",
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
  method: string,
  retries: number = 0
) {
  const options: any = {
    method,
    headers,
  };

  if (method.toUpperCase() === "PUT" || method.toUpperCase() === "POST") {
    options.data = JSON.stringify(requestBody);
  }

  // Use the new client setup to login
  async function do_call(
    retries: number = 0
  ): Promise<null | { response: APIResponse; responseBody: any }> {
    const response = await request.fetch(endpoint, options);

    let responseBody: any;
    try {
      responseBody = await response.json();
    } catch (e) {
      responseBody = null;
    }

    if (response.status() == 404 && retries < 10) {
      console.warn("Retry attempt", retries + 1);
      await sleep(500);
      return await do_call(retries + 1);
    }
    return { response, responseBody };
  }

  const { response, responseBody } = await do_call();

  if (response.status() >= 300) {
    const errors = await response.text();
    logger.error({ endpoint, method, errors }, "failed to call");
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

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
