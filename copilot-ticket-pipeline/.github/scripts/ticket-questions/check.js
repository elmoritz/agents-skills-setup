#!/usr/bin/env node
'use strict';
// Validate a ticket body before writing it — the same parser the workflow uses, plus the
// skill-side rules (required sections, block placement, trace tokens).
//   node .github/scripts/ticket-questions/check.js <body-file> [--type feature|bug|unknown]
// Prints JSON; exit code 0 = valid, 1 = errors, 2 = usage error.
//
// readyAllowed = no open questions AND nothing left to fold (F§6).

const fs = require('node:fs');
const F = require('./format.js');

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--') && args[args.indexOf(a) - 1] !== '--type');
const typeIdx = args.indexOf('--type');
const type = typeIdx >= 0 ? args[typeIdx + 1] : undefined;
if (!file || (type && !['feature', 'bug', 'unknown'].includes(type))) {
  console.error('usage: check.js <body-file> [--type feature|bug|unknown]');
  process.exit(2);
}

const result = F.lint(fs.readFileSync(file, 'utf8'), { type });
result.readyAllowed = result.ok && result.open.length === 0 && result.pendingToFold.length === 0;
console.log(JSON.stringify(result, null, 2));
process.exit(result.ok ? 0 : 1);
