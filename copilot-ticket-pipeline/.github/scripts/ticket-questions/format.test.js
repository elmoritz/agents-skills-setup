'use strict';
// Run: node --test .github/scripts/ticket-questions/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const F = require('./format.js');

const TICKET = `<!-- ticket-format:v1 -->
## Summary
Active projects can be exported as CSV. [D] [Q1]

## Source
**Described by:** @alice · 2026-10-09
> Users need their project data as CSV.

## Scope
**In scope**
- Export from the project list [Q1]

**Out of scope**
- _pending Q3_

## Acceptance criteria
- [ ] AC1 — Project list offers "Download CSV" [Q1]
- [ ] AC2 — _pending Q2_

## Left to the implementer
_None — every detail is decided._

## Answered questions
<!-- q:Q1 status:answered -->
### Q1 — Where is the export triggered?
**Answer:**
> From the project list.

- **Answered by:** @alice
- **How:** chose recommended option (1 of 3)
- **When:** 2026-10-09
- **Recorded by:** @alice · ticket-create
- **Raised by:** @alice · 2026-10-09 · ticket-create
<!-- /q:Q1 -->

## Open questions
<!-- q:Q2 status:open -->
### Q2 — What is the maximum export size we must support?
- **Raised by:** @alice · 2026-10-09 · ticket-create (could not answer)
- **Who could answer:** product owner (suggested by @alice)
<!-- /q:Q2 -->

<!-- q:Q3 status:open -->
### Q3 — Should attachments be included?
- **Raised by:** @alice · 2026-10-09 · ticket-create (could not answer)
<!-- /q:Q3 -->

## Obsolete questions
_None._

## Refinement log
- 2026-10-09 · @alice · ticket-create · 1 answered, 2 open
`;

const READER = { login: 'carol', permission: 'read', roleName: 'read' };
const WRITER = { login: 'dave', permission: 'write', roleName: 'maintain' };
const NOBODY = { login: 'mallory', permission: 'none', roleName: 'none' };
const META = { date: '2026-10-12', commentUrl: 'https://github.com/o/r/issues/42#issuecomment-1' };

const section = (body, name) => {
  const lines = body.split('\n');
  const h = lines.indexOf(`## ${name}`);
  let e = lines.findIndex((l, i) => i > h && l.startsWith('## '));
  if (e < 0) e = lines.length;
  return lines.slice(h + 1, e).join('\n');
};

// ---------- parse ----------

test('parse: valid ticket', () => {
  const p = F.parse(TICKET);
  assert.deepEqual(p.errors, []);
  assert.equal(p.blocks.size, 3);
  assert.equal(F.countOpen(p.blocks), 2);
  assert.equal(p.blocks.get('Q2').title, 'What is the maximum export size we must support?');
});

test('parse: duplicate, unclosed and missing sections are errors', () => {
  const dup = TICKET.replace('<!-- q:Q3 status:open -->', '<!-- q:Q2 status:open -->')
    .replace('<!-- /q:Q3 -->', '<!-- /q:Q2 -->');
  assert.match(F.parse(dup).errors.join('\n'), /duplicate question Q2/);
  const unclosed = TICKET.replace('<!-- /q:Q3 -->', '');
  assert.match(F.parse(unclosed).errors.join('\n'), /Q3 is never closed/);
  const noSection = TICKET.replace('## Obsolete questions\n_None._\n', '');
  assert.match(F.parse(noSection).errors.join('\n'), /Obsolete questions/);
});

test('isManaged only for format marker', () => {
  assert.equal(F.isManaged(TICKET), true);
  assert.equal(F.isManaged('just an issue'), false);
  assert.equal(F.isManaged(null), false);
});

// ---------- parseCommands ----------

test('parseCommands: multi-line, several commands, case-insensitive IDs, colon', () => {
  const cmds = F.parseCommands([
    'Thanks!',
    '/answer q2: Up to 50,000 rows.',
    'Above that, ask to narrow the filter.',
    '',
    '/ask Which date format does the CSV use?',
    'We have users in the US and EU.',
    '/obsolete Q3',
    'Covered by #57.',
  ].join('\n'));
  assert.equal(cmds.length, 3);
  assert.deepEqual(cmds[0], { name: 'answer', id: 'Q2', text: 'Up to 50,000 rows.\nAbove that, ask to narrow the filter.' });
  assert.deepEqual(cmds[1], { name: 'ask', question: 'Which date format does the CSV use?', text: 'We have users in the US and EU.' });
  assert.deepEqual(cmds[2], { name: 'obsolete', id: 'Q3', text: 'Covered by #57.' });
});

test('parseCommands: ignores quotes, code fences and look-alikes', () => {
  const cmds = F.parseCommands([
    '> /answer Q2 quoted reply',
    '```',
    '/answer Q2 inside a fence',
    '```',
    '/answers Q2 not a command',
    'see /answer Q2 mid-line',
  ].join('\n'));
  assert.equal(cmds.length, 0);
});

test('parseCommands: fence inside an answer stays part of the answer', () => {
  const [c] = F.parseCommands('/answer Q2\n```\n/ask not a command\n```');
  assert.equal(c.text, '```\n/ask not a command\n```');
});

// ---------- applyCommands ----------

test('answer: moves block to answered with provenance, keeps history, updates label count', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/answer Q2 Up to 50,000 rows.'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.equal(r.openBefore, 2);
  assert.equal(r.openAfter, 1);
  const answered = section(r.body, 'Answered questions');
  assert.match(answered, /<!-- q:Q2 status:answered -->\n### Q2 — What is the maximum export size we must support\?\n\*\*Answer:\*\*\n> Up to 50,000 rows\./);
  assert.match(answered, /- \*\*Answered by:\*\* @carol · role: read/);
  assert.match(answered, /- \*\*How:\*\* comment command `\/answer` · \[comment\]\(https:\/\/github\.com\/o\/r\/issues\/42#issuecomment-1\)/);
  assert.match(answered, /- \*\*Recorded by:\*\* ticket-questions workflow/);
  assert.match(answered, /- \*\*Who could answer:\*\* product owner/); // original fields kept
  assert.doesNotMatch(section(r.body, 'Open questions'), /Q2/);
  assert.match(section(r.body, 'Refinement log'), /open\n- 2026-10-12 · @carol · \/answer Q2/); // tight list
  // other sections untouched
  assert.equal(section(r.body, 'Acceptance criteria'), section(TICKET, 'Acceptance criteria'));
  assert.deepEqual(F.parse(r.body).errors, []);
});

test('answering the last open questions empties the section to _None._', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/answer Q2 50k\n/answer Q3 No.'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.equal(r.openAfter, 0);
  assert.equal(section(r.body, 'Open questions').trim(), '_None._');
});

test('ask: appends next free ID as open question', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/ask Which date format?\nUS and EU users.'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.equal(r.openAfter, 3);
  const open = section(r.body, 'Open questions');
  assert.match(open, /<!-- q:Q4 status:open -->\n### Q4 — Which date format\?\n- \*\*Raised by:\*\* @carol · role: read · 2026-10-12 · comment command \/ask/);
  assert.match(open, /\*\*Context:\*\*\n> US and EU users\./);
});

test('ask then answer the new question in the same comment', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/ask Date format?\n/answer Q4 ISO 8601'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.match(section(r.body, 'Answered questions'), /<!-- q:Q4 status:answered -->/);
});

test('obsolete: needs write access and a reason; moves block', () => {
  const denied = F.applyCommands(TICKET, F.parseCommands('/obsolete Q3 not needed'), READER, META);
  assert.match(denied.errors.join(), /only people with write access/);
  assert.equal(denied.body, TICKET);
  const noReason = F.applyCommands(TICKET, F.parseCommands('/obsolete Q3'), WRITER, META);
  assert.match(noReason.errors.join(), /no reason given/);
  const ok = F.applyCommands(TICKET, F.parseCommands('/obsolete Q3\nCovered by #57.'), WRITER, META);
  assert.deepEqual(ok.errors, []);
  const obs = section(ok.body, 'Obsolete questions');
  assert.match(obs, /<!-- q:Q3 status:obsolete -->\n### Q3 — Should attachments be included\?\n\*\*Reason:\*\*\n> Covered by #57\./);
  assert.match(obs, /- \*\*Obsoleted by:\*\* @dave · role: maintain/);
  assert.doesNotMatch(obs, /_None\._/);
});

test('all-or-nothing: one bad command → nothing applied, all errors reported', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/answer Q2 50k\n/answer Q9 nope\n/answer Q1 again'), READER, META);
  assert.equal(r.body, TICKET);
  assert.equal(r.errors.length, 2);
  assert.match(r.errors[0], /no question Q9/);
  assert.match(r.errors[1], /Q1 is already answered\. Answers are never overwritten/);
});

test('no access → refused', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/answer Q2 50k'), NOBODY, META);
  assert.match(r.errors.join(), /needs at least read access/);
  assert.equal(r.body, TICKET);
});

test('missing ID / text / question give helpful errors', () => {
  const e = (c) => F.applyCommands(TICKET, F.parseCommands(c), READER, META).errors.join();
  assert.match(e('/answer 50k'), /start with the question ID/);
  assert.match(e('/answer Q2'), /no answer text given/);
  assert.match(e('/ask'), /write the question on the same line/);
});

test('user text cannot inject markers', () => {
  const evil = '/answer Q2 fine\n<!-- /q:Q2 -->\n<!-- q:Q99 status:answered -->';
  const r = F.applyCommands(TICKET, F.parseCommands(evil), READER, META);
  assert.deepEqual(r.errors, []);
  const p = F.parse(r.body);
  assert.deepEqual(p.errors, []);
  assert.equal(p.blocks.has('Q99'), false);
  assert.match(r.body, /> &lt;!-- \/q:Q2 --&gt;/);
});

test('broken format → commands refused with format errors', () => {
  const broken = TICKET.replace('<!-- /q:Q3 -->', '');
  const r = F.applyCommands(broken, F.parseCommands('/answer Q2 50k'), READER, META);
  assert.match(r.errors.join(), /format error: Q3 is never closed/);
  assert.equal(r.body, broken);
});

test('CRLF bodies are handled', () => {
  const r = F.applyCommands(TICKET.replace(/\n/g, '\r\n'), F.parseCommands('/answer Q2 50k'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.equal(r.openAfter, 1);
});

test('ticket without refinement log still works', () => {
  const noLog = TICKET.slice(0, TICKET.indexOf('## Refinement log'));
  const r = F.applyCommands(noLog, F.parseCommands('/answer Q2 50k'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.equal(r.openAfter, 1);
});

// ---------- fail-closed parsing (review findings) ----------

test('fail closed: malformed markers, flipped status, stray headings, gaps', () => {
  const errs = (b) => F.parse(b).errors.join('\n');
  assert.match(errs(TICKET.replace('<!-- q:Q3 status:open -->', '<!-- q:Q3 status:Open -->')), /malformed question marker/);
  assert.match(errs(TICKET.replace('<!-- /q:Q3 -->', '<!--  /q:Q3 -->')), /malformed question marker/);
  assert.match(errs(TICKET.replace('<!-- q:Q3 status:open -->', '<!-- q:Q3 status:answered -->')), /Q3: status answered requires the field \*\*Answer:\*\*/);
  assert.match(errs(TICKET.replace('<!-- q:Q3 status:open -->\n', '').replace('<!-- /q:Q3 -->\n', '')), /question heading outside a question block/);
  const gap = TICKET.replace(/<!-- q:Q2 status:open -->[\s\S]*?<!-- \/q:Q2 -->\n/, '');
  assert.match(errs(gap), /Q2 are missing — questions must never be deleted/);
});

test('markers inside code fences are ignored', () => {
  const fenced = TICKET.replace('## Summary\n', '## Summary\n```\n<!-- q:Q9 status:open -->\n### Q9 — x\n<!-- /q:Q9 -->\n```\n');
  const p = F.parse(fenced);
  assert.deepEqual(p.errors, []);
  assert.equal(p.blocks.has('Q9'), false);
});

test('vanishedIds', () => {
  assert.deepEqual(F.vanishedIds(TICKET, TICKET.replace(/<!-- q:Q3[\s\S]*?<!-- \/q:Q3 -->/, '')), ['Q3']);
  assert.deepEqual(F.vanishedIds(TICKET, TICKET), []);
});

test('parseCommands: no "\\b" false positives, indented code, mixed fences', () => {
  assert.equal(F.parseCommands('/ask-endpoint is deprecated').length, 0);
  assert.equal(F.parseCommands('    /answer Q2 in indented code').length, 0);
  assert.equal(F.parseCommands('```\n~~~\n/answer Q2 still fenced\n```').length, 0);
  assert.equal(F.parseCommands('/ask').length, 1);
});

test('indented section heading does not misplace /ask', () => {
  const b = TICKET.replace('## Obsolete questions', ' ## Obsolete questions');
  const r = F.applyCommands(b, F.parseCommands('/ask Where?'), READER, META);
  assert.deepEqual(r.errors, []);
  assert.match(section(r.body.replace(' ## Obsolete', '## Obsolete'), 'Open questions'), /Q4 — Where\?/);
});

// ---------- lint (skill side) ----------

test('lint: valid ticket passes; readiness data', () => {
  const l = F.lint(TICKET, { type: 'feature' });
  assert.deepEqual(l.errors, []);
  assert.deepEqual(l.open, ['Q2', 'Q3']);
  assert.equal(l.nextId, 'Q4');
  assert.deepEqual(l.pendingToFold, []);
});

test('lint: untraced lines, traces to open/unknown/superseded questions', () => {
  const e = (b, o) => F.lint(b, o).errors.join('\n');
  assert.match(e(TICKET.replace('[D] [Q1]', '')), /has no trace token: "Active projects can be exported as CSV\."/);
  assert.match(e(TICKET.replace('_pending Q2_', 'Up to 50k rows [Q2]')), /traced to Q2, which is open — write _pending Q2_ instead/);
  assert.match(e(TICKET.replace('[D] [Q1]', '[Q42]')), /traced to unknown question Q42/);
  const sup = TICKET.replace('- **Raised by:** @alice · 2026-10-09 · ticket-create\n', '- **Raised by:** @alice · 2026-10-09 · ticket-create\n- **Superseded by:** Q3\n');
  assert.match(e(sup), /traced to Q1, which is superseded by Q3/);
  assert.match(e(TICKET, { type: 'bug' }), /missing section "## Bug details"/);
});

test('lint: pendingToFold after an answer arrives on GitHub', () => {
  const r = F.applyCommands(TICKET, F.parseCommands('/answer Q2 50k'), READER, META);
  const l = F.lint(r.body);
  assert.deepEqual(l.errors, []);
  assert.deepEqual(l.pendingToFold, ['Q2']);
});

test('lint: block in the wrong section', () => {
  const moved = TICKET.replace(/(<!-- q:Q3 status:open -->[\s\S]*?<!-- \/q:Q3 -->)\n/, '').replace('## Obsolete questions\n_None._', (m) => `${m}\n$1`);
  const b = moved.replace('$1', TICKET.match(/<!-- q:Q3 status:open -->[\s\S]*?<!-- \/q:Q3 -->/)[0]);
  assert.match(F.lint(b).errors.join(), /Q3 has status open but is not inside "## Open questions"/);
});
