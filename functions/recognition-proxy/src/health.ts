import type { HttpResponseInit } from "@azure/functions";

export async function health(): Promise<HttpResponseInit> {
  return {
    status: 200,
    jsonBody: {
      status: "Healthy",
      runtime: "recognition-proxy"
    },
    headers: {
      "Cache-Control": "no-store"
    }
  };
}
