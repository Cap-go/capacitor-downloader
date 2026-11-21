#!/usr/bin/env node
import { appendFileSync } from 'node:fs';

const scenario = process.env.SCENARIO ?? 'all';
const mode = process.env.MODE ?? 'both';

const androidRows = [
  {
    regression: 'completion-dedupe',
    flow: 'completion-once',
    mode: 'broken',
    expect_outcome: 'failure',
  },
  {
    regression: 'completion-dedupe',
    flow: 'completion-once',
    mode: 'fixed',
    expect_outcome: 'success',
  },
  {
    regression: 'cancel-cleanup',
    flow: 'cancel-cleanup',
    mode: 'broken',
    expect_outcome: 'failure',
  },
  {
    regression: 'cancel-cleanup',
    flow: 'cancel-cleanup',
    mode: 'fixed',
    expect_outcome: 'success',
  },
  {
    regression: 'error-404-map',
    flow: 'error-404',
    mode: 'broken',
    expect_outcome: 'failure',
  },
  {
    regression: 'error-404-map',
    flow: 'error-404',
    mode: 'fixed',
    expect_outcome: 'success',
  },
];

const iosRows = [
  {
    regression: 'completion-dedupe',
    flow: 'completion-once',
    mode: 'broken',
    expect_outcome: 'failure',
  },
  {
    regression: 'completion-dedupe',
    flow: 'completion-once',
    mode: 'fixed',
    expect_outcome: 'success',
  },
  {
    regression: 'error-404-map',
    flow: 'error-404',
    mode: 'broken',
    expect_outcome: 'failure',
  },
  {
    regression: 'error-404-map',
    flow: 'error-404',
    mode: 'fixed',
    expect_outcome: 'success',
  },
];

function filterRows(rows) {
  return rows.filter((row) => {
    if (scenario !== 'all' && scenario !== row.flow) {
      return false;
    }
    if (mode !== 'both' && mode !== row.mode) {
      return false;
    }
    return true;
  });
}

const androidMatrix = filterRows(androidRows);
const iosMatrix = filterRows(iosRows);

const outputPath = process.env.GITHUB_OUTPUT;
if (!outputPath) {
  console.log(JSON.stringify({ androidMatrix, iosMatrix }, null, 2));
  process.exit(0);
}

function writeOutput(name, value) {
  appendFileSync(outputPath, `${name}=${value}\n`);
}

writeOutput('android_matrix', JSON.stringify(androidMatrix));
writeOutput('ios_matrix', JSON.stringify(iosMatrix));
writeOutput('android_enabled', androidMatrix.length > 0 ? 'true' : 'false');
writeOutput('ios_enabled', iosMatrix.length > 0 ? 'true' : 'false');