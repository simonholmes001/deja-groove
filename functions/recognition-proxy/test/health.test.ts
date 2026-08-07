import assert from "node:assert/strict";
import test from "node:test";
import { health } from "../src/health.js";

test("health returns runtime and deployment marker", async () => {
  const response = await health();
  const body = response.jsonBody as {
    status: string;
    runtime: string;
    deployment: {
      packageVersion: string;
    };
  };

  assert.equal(response.status, 200);
  assert.equal(body.status, "Healthy");
  assert.equal(body.runtime, "recognition-proxy");
  assert.equal(typeof body.deployment.packageVersion, "string");
  assert.ok(body.deployment.packageVersion.length > 0);
});
