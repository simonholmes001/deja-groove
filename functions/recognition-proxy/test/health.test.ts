import assert from "node:assert/strict";
import test from "node:test";
import { health } from "../src/health.js";

test("health returns runtime without deployment marker by default", async () => {
  const response = await health();
  const body = response.jsonBody as {
    status: string;
    runtime: string;
    deployment?: unknown;
  };

  assert.equal(response.status, 200);
  assert.equal(body.status, "Healthy");
  assert.equal(body.runtime, "recognition-proxy");
  assert.equal(body.deployment, undefined);
});

test("health returns deployment marker when explicitly enabled", async () => {
  process.env.HEALTH_INCLUDE_DEPLOYMENT = "true";
  try {
    const response = await health();
    const body = response.jsonBody as {
      deployment: {
        packageVersion: string;
      };
    };

    assert.equal(response.status, 200);
    assert.equal(typeof body.deployment.packageVersion, "string");
    assert.ok(body.deployment.packageVersion.length > 0);
  } finally {
    delete process.env.HEALTH_INCLUDE_DEPLOYMENT;
  }
});
