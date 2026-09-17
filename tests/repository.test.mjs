import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (relative) => readFileSync(join(root, relative), 'utf8');
const setup = read('sql/30_incremental_ai_enrichment.sql');
const scoring = read('sql/31_score_approved_batch.sql');
const costs = read('sql/40_cost_observability.sql');
const html = read('docs/tool-decision-matrix.html');

test('fixture tests exercise the same null-safe hash as the scoring source', () => {
  const expression = 'SHA2(TO_JSON(ARRAY_CONSTRUCT(TITLE_ID, AUTHOR_HASH, ITEM_TEXT)), 256)';
  assert.ok(setup.includes(expression));
  assert.ok(read('tests/enrichment_regression.sql').includes(expression));
  assert.doesNotMatch(setup, /CONCAT_WS/);
  assert.match(setup, /WHERE TITLE_ID IS NOT NULL/);
});

test('preflight has no inference and estimates both actual functions', () => {
  assert.doesNotMatch(setup, /\bAI_(?:SENTIMENT|CLASSIFY)\s*\(/);
  assert.match(setup, /AI_COUNT_TOKENS\('ai_sentiment', ITEM_TEXT\)/);
  assert.match(setup, /AI_COUNT_TOKENS\('ai_classify', ITEM_TEXT, CATEGORIES, CLASSIFY_CONFIG\)/);
  assert.match(setup, /SET SCORING_APPROVED = FALSE/);
  assert.match(setup, /ORDER BY ITEM_HASH\s+LIMIT 100/);
  assert.match(setup, /COUNT\(\*\) - COUNT\(SENTIMENT_INPUT_TOKENS \+ CLASSIFY_INPUT_TOKENS\)/);
});

test('scoring requires explicit approval and a complete bounded estimate', () => {
  assert.doesNotMatch(scoring, /^SET SCORING_APPROVED = TRUE/m);
  assert.match(scoring, /WHERE \$SCORING_APPROVED = TRUE/);
  assert.match(scoring, /estimate.NULL_ESTIMATE_ROWS = 0/);
  assert.match(scoring, /estimate.TOTAL_INPUT_TOKENS <= estimate.INPUT_TOKEN_CEILING/);
  assert.match(scoring, /SET SCORING_APPROVED = FALSE/);
});

test('candidate selection and persistence match content and scorer version', () => {
  assert.match(setup, /result.ITEM_HASH = item.ITEM_HASH\s+AND result.SCORER_VERSION = config.SCORER_VERSION/);
  assert.match(scoring, /result.ITEM_HASH = batch.ITEM_HASH AND result.SCORER_VERSION = batch.SCORER_VERSION/);
  assert.match(scoring, /ON target.ITEM_HASH = source.ITEM_HASH AND target.SCORER_VERSION = source.SCORER_VERSION/);
  assert.doesNotMatch(scoring, /WHEN MATCHED THEN UPDATE/);
  assert.match(scoring, /REVIEW_REQUIRED/);
});

test('inference is materialized before parsing and persistence', () => {
  assert.equal((scoring.match(/AI_SENTIMENT\(/g) ?? []).length, 1);
  assert.equal((scoring.match(/AI_CLASSIFY\(/g) ?? []).length, 1);
  assert.ok(scoring.indexOf('TEXT_SCORING_RESPONSES AS') < scoring.indexOf('MERGE INTO'));
  assert.match(scoring, /SET SCORING_QUERY_ID = LAST_QUERY_ID\(\)/);
});

test('response fixtures use the same success predicate as persistence', () => {
  const predicate = /CASE WHEN SENTIMENT IN[\s\S]*?END AS SCORE_STATUS/;
  assert.equal(scoring.match(predicate)[0], read('tests/response_regression.sql').match(predicate)[0]);
  assert.match(scoring, /IS_NULL_VALUE\(SENTIMENT_RESPONSE:error\)/);
  assert.match(scoring, /IS_NULL_VALUE\(INTENT_RESPONSE:error\)/);
});

test('cost SQL uses current views, bounded windows, and no fake answer denominator', () => {
  assert.match(costs, /CORTEX_AI_FUNCTIONS_USAGE_HISTORY/);
  assert.match(costs, /SNOWFLAKE_COCO_USAGE_HISTORY/);
  assert.doesNotMatch(costs, /ACCOUNT_USAGE\.CORTEX_FUNCTIONS_(?:QUERY_)?USAGE_HISTORY/);
  assert.doesNotMatch(costs, /COUNT\(\*\)\s+AS (?:CALLS|AI_CALLS|ANSWERS)/);
  assert.doesNotMatch(costs, /-90/);
  assert.doesNotMatch(read('sql/41_enrichment_run_cost.sql'), /COALESCE\([^)]*CREDITS[^)]*,\s*0\)/);
});

test('quality evaluation keeps missing predictions and blocks absent class support', () => {
  const quality = read('sql/32_enrichment_quality.sql');
  assert.match(quality, /LEFT JOIN STUDIO_DS.CURATED.TEXT_ENRICHMENT_RESULT/);
  assert.match(quality, /OR evaluated.PRED_INTENT IS NULL/);
  assert.match(quality, /MIN\(CLASS_SUPPORT\) OVER \(\) > 0/);
  assert.match(quality, /STOP: empty gold set/);
});

test('project instructions use the discoverable filename without a duplicate', () => {
  assert.ok(existsSync(join(root, 'AGENTS.md')));
  assert.ok(!existsSync(join(root, 'COCO.md')));
  assert.ok(read('AGENTS.md').split('\n').length < 80);
});

test('HTML is offline-safe and has parseable provenance and unique anchors', () => {
  assert.doesNotMatch(html, /<script[^>]+src\s*=|<iframe|<canvas|@import|\bon(?:click|load|error)\s*=/i);
  assert.doesNotMatch(html, /\b(?:fetch|XMLHttpRequest|WebSocket|eval)\s*\(/);
  assert.doesNotMatch(html, /<(?:img|link)[^>]+(?:src|href)\s*=\s*["']https?:/i);
  assert.match(html, /name="snowflake-source"/);
  const metadata = JSON.parse(html.match(/id="snowflake-report-metadata">\s*([\s\S]*?)<\/script>/)[1]);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(ids.length, new Set(ids).size);
  for (const section of metadata.sections) assert.ok(ids.includes(section.id));
});

test('markdown relative links resolve', () => {
  const walk = (folder) => readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name.startsWith('.')) return [];
    const path = join(folder, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
  for (const path of walk(root).filter((path) => path.endsWith('.md'))) {
    for (const match of readFileSync(path, 'utf8').matchAll(/\]\(([^\s)]+)\)/g)) {
      if (/^(?:https?:|#|mailto:)/.test(match[1])) continue;
      assert.ok(existsSync(resolve(dirname(path), match[1].split('#')[0])), `${path}: ${match[1]}`);
    }
  }
});