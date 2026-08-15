import assert from "node:assert/strict";
import test from "node:test";
import { defaultEnrichmentTimeoutMs } from "../src/scan.js";
import { scanEnrichmentTimeoutMs } from "../src/runtimeConfig.js";

test("scanEnrichmentTimeoutMs uses the scan module default when app setting is absent", () => {
  assert.equal(scanEnrichmentTimeoutMs(undefined), defaultEnrichmentTimeoutMs);
});

test("scanEnrichmentTimeoutMs accepts a positive app setting override", () => {
  assert.equal(scanEnrichmentTimeoutMs("20000"), 20000);
});

test("scanEnrichmentTimeoutMs falls back to the scan default for invalid app settings", () => {
  assert.equal(scanEnrichmentTimeoutMs("not-a-number"), defaultEnrichmentTimeoutMs);
  assert.equal(scanEnrichmentTimeoutMs("0"), defaultEnrichmentTimeoutMs);
});
