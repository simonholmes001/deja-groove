import type { HttpResponseInit } from "@azure/functions";
import { readFile } from "node:fs/promises";

type DeploymentMarker = {
  packageVersion: string;
};

async function loadDeploymentMarker(): Promise<DeploymentMarker> {
  try {
    const markerUrl = new URL("../deployment-marker.json", import.meta.url);
    const marker = JSON.parse(await readFile(markerUrl, "utf8")) as Partial<DeploymentMarker>;
    return {
      packageVersion: marker.packageVersion || "local"
    };
  } catch {
    return {
      packageVersion: "local"
    };
  }
}

export async function health(): Promise<HttpResponseInit> {
  const includeDeployment = process.env.HEALTH_INCLUDE_DEPLOYMENT === "true";
  const deployment = includeDeployment ? await loadDeploymentMarker() : undefined;

  return {
    status: 200,
    jsonBody: {
      status: "Healthy",
      runtime: "recognition-proxy",
      ...(deployment ? { deployment } : {})
    },
    headers: {
      "Cache-Control": "no-store"
    }
  };
}
