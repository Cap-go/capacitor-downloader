#!/usr/bin/env bun
/**
 * Guards the break-fix regression matrix: a negative case must throw from the callback,
 * not from our own assertion after a non-throwing callback.
 */
export function expectBreakThrows(testCase) {
  let callbackError;
  try {
    testCase.break();
  } catch (error) {
    callbackError = error;
  }
  if (!callbackError) {
    throw new Error(`Expected ${testCase.name} break() to throw`);
  }
}