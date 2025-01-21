import { APIRequestContext } from "playwright";

type KongProvisionResponse = {
  status: number;
  body: any;
};

export async function provisionKong(
  request: APIRequestContext,
  endpoint: string,
  payload: any
) {
  const options: any = {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    data: JSON.stringify(payload),
  };

  const response = await request.fetch(endpoint, options);

  let responseBody: any;
  try {
    responseBody = await response.json();
  } catch (e) {
    responseBody = null;
  }

  return {
    status: response.status(),
    body: responseBody,
  } as KongProvisionResponse;
}
