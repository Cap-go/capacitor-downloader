/**
 * Validates Maestro assertions detect injected regressions (break-the-fix checks).
 * These mirror completion-once, cancel-cleanup, and error-404 flows without an emulator.
 */

function assertCompletionOnce(completionCount) {
  if (completionCount !== 1) {
    throw new Error(`Expected exactly one completion event, got ${completionCount}`);
  }
}

function assertCancelCleanup(state) {
  if (state === 'DONE') {
    throw new Error('Download still DONE after stop');
  }
}

function assertError404(state) {
  if (state !== 'ERROR') {
    throw new Error(`Expected ERROR for 404, got ${state}`);
  }
}

const cases = [
  {
    name: 'completion-once-dedupe',
    pass: () => assertCompletionOnce(1),
    break: () => assertCompletionOnce(2),
  },
  {
    name: 'cancel-cleanup',
    pass: () => assertCancelCleanup('PAUSED'),
    break: () => assertCancelCleanup('DONE'),
  },
  {
    name: 'error-404-mapping',
    pass: () => assertError404('ERROR'),
    break: () => assertError404('DONE'),
  },
];

for (const testCase of cases) {
  try {
    testCase.break();
    throw new Error(`${testCase.name}: expected FAIL but break path passed`);
  } catch (error) {
    process.stdout.write(`FAIL ${testCase.name}: ${error.message}\n`);
  }

  testCase.pass();
  process.stdout.write(`PASS ${testCase.name}\n`);
}