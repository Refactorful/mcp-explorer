// Minimal bindings for the handful of Vitest globals the test files use.

@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external test: (string, unit => 'a) => unit = "test"

type assertion

@module("vitest") external expect: 'a => assertion = "expect"

@send external toBe: (assertion, 'a) => unit = "toBe"
@send external toEqual: (assertion, 'a) => unit = "toEqual"
@send external toBeTruthy: assertion => unit = "toBeTruthy"
@send external toBeFalsy: assertion => unit = "toBeFalsy"
@send external toContain: (assertion, 'a) => unit = "toContain"
