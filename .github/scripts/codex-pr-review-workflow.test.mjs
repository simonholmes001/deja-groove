import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const workflow = readFileSync(new URL('../workflows/codex-pr-review.yaml', import.meta.url), 'utf8');
const keyCheck = workflow.split('      - name: Require OpenAI review key\n')[1]?.split('      - name: Run Codex review\n')[0];
const script = keyCheck?.split('        run: |\n')[1]?.replace(/^          /gm, '');

test('review fails visibly without a configured key', () => {
  assert.ok(script, 'the workflow must require a review key');
  const result = spawnSync('bash', ['-e', '-c', script], { env: { ...process.env, OPENAI_API_KEY: '' }, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /::error::/);
});

test('review accepts a configured key without printing it', () => {
  const key = 'synthetic-review-key';
  const result = spawnSync('bash', ['-e', '-c', script], { env: { ...process.env, OPENAI_API_KEY: key }, encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.ok(!(result.stdout + result.stderr).includes(key));
  assert.equal(workflow.match(/OPENAI_API_KEY: \$\{\{ secrets\.OPENAI_API_KEY \|\| secrets\.OPENAI_KEY \}\}/g)?.length, 2);
  assert.doesNotMatch(workflow, /if: steps\.detect-openai/);
});
