'use strict';
// Pure functions for ticket format v1 (.github/ticket-system/ticket-format.md).
// No I/O here — everything is unit-tested in format.test.js.

const FORMAT_MARKER = '<!-- ticket-format:v1 -->';
const NONE = '_None._';
const SECTIONS = {
  open: 'Open questions',
  answered: 'Answered questions',
  obsolete: 'Obsolete questions',
};
const LOG_SECTION = 'Refinement log';

const START_RE = /^<!-- q:(Q\d+) status:(open|answered|obsolete) -->$/;
const END_RE = /^<!-- \/q:(Q\d+) -->$/;
const ANY_MARKER_RE = /<!--\s*\/?\s*q\s*:/i; // anything that looks like a marker
const TITLE_RE = /^###\s+(Q\d+)\s+[—–-]\s+(.*)$/;
const COMMAND_RE = /^\/(answer|ask|obsolete)(?=\s|$)(.*)$/i;
const ID_RE = /^(q\d+)\b\s*(.*)$/i;
const FENCE_RE = /^ {0,3}(`{3,}|~{3,})/;

// Fields a block must carry for its status (F§4.2–4.4). Prevents "flipping" a
// marker by hand from silently closing a question.
const REQUIRED_FIELDS = {
  open: ['- **Raised by:**'],
  answered: ['**Answer:**', '- **Answered by:**', '- **How:**'],
  obsolete: ['**Reason:**', '- **Obsoleted by:**'],
};

const READ_OR_HIGHER = new Set(['read', 'write', 'admin']); // `permission` field of the collaborator API
const WRITE_OR_HIGHER = new Set(['write', 'admin']);

function isManaged(body) {
  return typeof body === 'string' && body.includes(FORMAT_MARKER);
}

function toLines(body) {
  return (body || '').replace(/\r\n/g, '\n').split('\n');
}

function idNum(id) {
  return Number(id.slice(1));
}

/** true for every line that is a code-fence line or inside a fenced code block */
function fenceMask(lines) {
  const mask = [];
  let open = null; // { ch, len }
  for (const line of lines) {
    const m = line.match(FENCE_RE);
    if (open) {
      mask.push(true);
      if (m && m[1][0] === open.ch && m[1].length >= open.len && line.trim() === m[1]) open = null;
    } else if (m) {
      mask.push(true);
      open = { ch: m[1][0], len: m[1].length };
    } else {
      mask.push(false);
    }
  }
  return mask;
}

/** Parse question blocks and check the structural rules of F§4 (fail closed). */
function parse(body) {
  const lines = toLines(body);
  const fenced = fenceMask(lines);
  const errors = [];
  const blocks = new Map();
  let cur = null;
  lines.forEach((line, i) => {
    if (fenced[i]) return;
    const t = line.trim();
    const s = t.match(START_RE);
    if (s) {
      if (cur) errors.push(`line ${i + 1}: ${s[1]} starts before ${cur.id} is closed`);
      if (blocks.has(s[1])) errors.push(`line ${i + 1}: duplicate question ${s[1]}`);
      cur = { id: s[1], status: s[2], start: i };
      return;
    }
    const e = t.match(END_RE);
    if (e) {
      if (!cur || cur.id !== e[1]) {
        errors.push(`line ${i + 1}: end marker for ${e[1]} without matching start`);
        return;
      }
      cur.end = i;
      const inner = lines.slice(cur.start + 1, i);
      const titleIdx = inner.findIndex((l) => TITLE_RE.test(l.trim()));
      cur.title = titleIdx >= 0 ? inner[titleIdx].trim().match(TITLE_RE)[2].trim() : '(untitled)';
      cur.details = titleIdx >= 0 ? inner.slice(titleIdx + 1) : inner;
      if (titleIdx < 0) errors.push(`${cur.id}: missing heading "### ${cur.id} — <question>"`);
      const text = cur.details.map((l) => l.trim());
      for (const field of REQUIRED_FIELDS[cur.status]) {
        if (!text.some((l) => l.startsWith(field))) {
          errors.push(`${cur.id}: status ${cur.status} requires the field ${field.replace(/^- /, '')}`);
        }
      }
      cur.superseded = (text.find((l) => l.startsWith('- **Superseded by:**')) || '').match(/Q\d+/)?.[0] || null;
      if (!blocks.has(cur.id)) blocks.set(cur.id, cur);
      cur = null;
      return;
    }
    if (ANY_MARKER_RE.test(t)) errors.push(`line ${i + 1}: malformed question marker "${t.slice(0, 60)}"`);
    if (!cur && TITLE_RE.test(t)) errors.push(`line ${i + 1}: question heading outside a question block (markers missing?)`);
  });
  if (cur) errors.push(`${cur.id} is never closed (missing <!-- /q:${cur.id} -->)`);
  for (const name of Object.values(SECTIONS)) {
    const n = lines.filter((l, i) => !fenced[i] && l.trim() === `## ${name}`).length;
    if (n !== 1) errors.push(`section "## ${name}" must appear exactly once (found ${n})`);
  }
  // IDs are never deleted or reused, so they must run Q1..Qmax without gaps (F§4.1).
  const nums = [...blocks.keys()].map(idNum).sort((a, b) => a - b);
  const missing = [];
  for (let n = 1; n <= (nums[nums.length - 1] || 0); n += 1) if (!nums.includes(n)) missing.push(`Q${n}`);
  if (missing.length) errors.push(`question(s) ${missing.join(', ')} are missing — questions must never be deleted`);
  return { lines, blocks, errors };
}

/** IDs present in `before` but gone in `after` (for issue edits). */
function vanishedIds(before, after) {
  const re = /<!-- q:(Q\d+) status:/g;
  const a = new Set([...(after || '').matchAll(re)].map((m) => m[1]));
  return [...new Set([...(before || '').matchAll(re)].map((m) => m[1]))].filter((id) => !a.has(id));
}

function countOpen(blocks) {
  let n = 0;
  for (const b of blocks.values()) if (b.status === 'open') n += 1;
  return n;
}

/** Escape marker syntax so user text can never open or close a block. */
function sanitize(text) {
  return String(text).replace(/<!--/g, '&lt;!--').replace(/-->/g, '--&gt;');
}

function quote(text) {
  return sanitize(text)
    .split('\n')
    .map((l) => (l.trimEnd() ? `> ${l.trimEnd()}` : '>'))
    .join('\n');
}

function oneLine(text) {
  return sanitize(text).replace(/\s+/g, ' ').trim();
}

/** Split a comment into commands (§ 7). Lines in code fences or quotes never start a command. */
function parseCommands(text) {
  const cmds = [];
  let cur = null;
  const lines = toLines(text);
  const fenced = fenceMask(lines);
  for (const [i, raw] of lines.entries()) {
    const t = raw.trim();
    const indentedCode = /^( {4}|\t)/.test(raw);
    const m = fenced[i] || indentedCode ? null : t.match(COMMAND_RE);
    if (m) {
      cur = { name: m[1].toLowerCase(), args: m[2].trim(), rest: [] };
      cmds.push(cur);
      continue;
    }
    if (cur) cur.rest.push(raw);
  }
  return cmds.map((c) => {
    const restText = c.rest.join('\n').trim();
    if (c.name === 'ask') {
      return { name: 'ask', question: c.args, text: restText };
    }
    const m = c.args.match(ID_RE);
    if (!m) return { name: c.name, id: null, text: '', raw: c.args };
    const sameLine = m[2].replace(/^[:\-–—]\s*/, '').trim(); // allow "/answer Q2: text"
    const text = [sameLine, restText].filter(Boolean).join('\n').trim();
    return { name: c.name, id: m[1].toUpperCase(), text };
  });
}

// ---------- line-array editing helpers ----------

function sectionRange(lines, name) {
  const fenced = fenceMask(lines);
  const head = lines.findIndex((l, i) => !fenced[i] && l.trim() === `## ${name}`);
  if (head < 0) return null;
  let end = lines.length;
  for (let i = head + 1; i < lines.length; i += 1) {
    if (!fenced[i] && /^## /.test(lines[i].trim())) {
      end = i;
      break;
    }
  }
  return { head, end };
}

function findBlock(lines, id) {
  const start = lines.findIndex((l) => {
    const m = l.trim().match(START_RE);
    return m && m[1] === id;
  });
  if (start < 0) return null;
  const end = lines.findIndex((l, i) => i > start && l.trim() === `<!-- /q:${id} -->`);
  return end < 0 ? null : { start, end };
}

/** Remove placeholder / tidy blank lines inside one question or log section. */
function normalizeSection(lines, name) {
  const r = sectionRange(lines, name);
  if (!r) return lines;
  const content = lines.slice(r.head + 1, r.end).filter((l) => l.trim() !== NONE);
  const hasContent = content.some((l) => l.trim() !== '');
  const tidy = [];
  for (const l of content) {
    if (l.trim() === '' && (tidy.length === 0 || tidy[tidy.length - 1].trim() === '')) continue;
    tidy.push(l);
  }
  while (tidy.length && tidy[tidy.length - 1].trim() === '') tidy.pop();
  const body = hasContent ? tidy : [NONE];
  const trailer = r.end < lines.length ? [''] : [];
  return [...lines.slice(0, r.head + 1), ...body, ...trailer, ...lines.slice(r.end)];
}

function appendToSection(lines, name, newLines, { separate = true } = {}) {
  const r = sectionRange(lines, name);
  if (!r) return lines;
  let insertAt = r.end;
  while (insertAt > r.head + 1 && lines[insertAt - 1].trim() === '') insertAt -= 1;
  const gap = separate ? [''] : [];
  return [...lines.slice(0, insertAt), ...gap, ...newLines, ...lines.slice(insertAt)];
}

function provenance(actor, meta, verb) {
  return [
    `- **${verb} by:** @${actor.login} · role: ${actor.roleName || actor.permission}`,
    `- **How:** comment command \`/${meta.command}\` · [comment](${meta.commentUrl})`,
    `- **When:** ${meta.date}`,
    '- **Recorded by:** ticket-questions workflow',
  ];
}

function trimDetails(details) {
  const d = [...details];
  while (d.length && d[0].trim() === '') d.shift();
  while (d.length && d[d.length - 1].trim() === '') d.pop();
  return d;
}

function resolveBlock(lines, block, status, label, text, actor, meta, verb) {
  const pos = findBlock(lines, block.id);
  const rebuilt = [
    `<!-- q:${block.id} status:${status} -->`,
    `### ${block.id} — ${block.title}`,
    `**${label}:**`,
    quote(text),
    '',
    ...provenance(actor, meta, verb),
    ...trimDetails(block.details),
    `<!-- /q:${block.id} -->`,
  ];
  const without = [...lines.slice(0, pos.start), ...lines.slice(pos.end + 1)];
  return appendToSection(without, SECTIONS[status], rebuilt);
}

/**
 * Apply all commands of one comment. All-or-nothing: on any error the original
 * body is returned unchanged together with every error found.
 */
function applyCommands(body, commands, actor, meta) {
  const initial = parse(body);
  if (initial.errors.length) {
    return { body, errors: initial.errors.map((e) => `format error: ${e}`), changes: [], openBefore: null, openAfter: null };
  }
  const openBefore = countOpen(initial.blocks);
  const errors = [];
  const changes = [];
  let lines = initial.lines;
  const canRead = READ_OR_HIGHER.has(actor.permission);
  const canWrite = WRITE_OR_HIGHER.has(actor.permission);

  for (const cmd of commands) {
    const { blocks } = parse(lines.join('\n'));
    const m = { ...meta, command: cmd.name };
    if (!canRead) {
      errors.push(`/${cmd.name}: @${actor.login} needs at least read access to this repository.`);
      continue;
    }
    if (cmd.name === 'ask') {
      if (!cmd.question) {
        errors.push('/ask: write the question on the same line, e.g. `/ask Which date format does the CSV use?`');
        continue;
      }
      const next = `Q${Math.max(0, ...[...blocks.keys()].map(idNum)) + 1}`;
      const block = [
        `<!-- q:${next} status:open -->`,
        `### ${next} — ${oneLine(cmd.question)}`,
        `- **Raised by:** @${actor.login} · role: ${actor.roleName || actor.permission} · ${meta.date} · comment command /ask · [comment](${meta.commentUrl})`,
      ];
      if (cmd.text) block.push('', '**Context:**', quote(cmd.text));
      block.push(`<!-- /q:${next} -->`);
      lines = appendToSection(lines, SECTIONS.open, block);
      changes.push(`/ask → ${next}`);
      continue;
    }
    // answer / obsolete
    if (!cmd.id) {
      errors.push(`/${cmd.name}: start with the question ID, e.g. \`/${cmd.name} Q2\`.`);
      continue;
    }
    const b = blocks.get(cmd.id);
    if (!b) {
      errors.push(`/${cmd.name} ${cmd.id}: this ticket has no question ${cmd.id}.`);
      continue;
    }
    if (b.status !== 'open') {
      const hint = cmd.name === 'answer'
        ? ' Answers are never overwritten — use `/ask` to raise a follow-up question instead.'
        : '';
      errors.push(`/${cmd.name} ${cmd.id}: ${cmd.id} is already ${b.status}.${hint}`);
      continue;
    }
    if (cmd.name === 'obsolete' && !canWrite) {
      errors.push(`/obsolete ${cmd.id}: only people with write access can obsolete a question (@${actor.login} has ${actor.permission}).`);
      continue;
    }
    if (!cmd.text) {
      const what = cmd.name === 'answer' ? 'answer text' : 'reason';
      errors.push(`/${cmd.name} ${cmd.id}: no ${what} given. Write it after the ID or on the following lines.`);
      continue;
    }
    lines = cmd.name === 'answer'
      ? resolveBlock(lines, b, 'answered', 'Answer', cmd.text, actor, m, 'Answered')
      : resolveBlock(lines, b, 'obsolete', 'Reason', cmd.text, actor, m, 'Obsoleted');
    changes.push(`/${cmd.name} ${cmd.id}`);
  }

  if (errors.length) return { body, errors, changes: [], openBefore, openAfter: openBefore };

  if (sectionRange(lines, LOG_SECTION)) {
    lines = appendToSection(lines, LOG_SECTION, [
      `- ${meta.date} · @${actor.login} · ${changes.join(', ')} · [comment](${meta.commentUrl})`,
    ], { separate: false });
  }
  for (const name of [...Object.values(SECTIONS), LOG_SECTION]) lines = normalizeSection(lines, name);

  const out = lines.join('\n');
  const after = parse(out);
  if (after.errors.length) {
    // Should never happen; refuse rather than write a broken ticket.
    return { body, errors: after.errors.map((e) => `internal error: ${e}`), changes: [], openBefore, openAfter: openBefore };
  }
  return { body: out, errors: [], changes, openBefore, openAfter: countOpen(after.blocks) };
}

// ---------- full lint for the skills (check.js) ----------

const BASE_SECTIONS = ['Summary', 'Source', 'Scope', 'Acceptance criteria', 'Left to the implementer',
  SECTIONS.answered, SECTIONS.open, SECTIONS.obsolete, LOG_SECTION];
const PROSE_SECTIONS = ['Summary', 'Scope', 'Bug details', 'Acceptance criteria', 'Left to the implementer'];
const TRACE_RE = /\[(D|R|Q\d+|@[A-Za-z0-9-]+)\]/g;
const PENDING_RE = /_pending (Q\d+)_/g;

/**
 * Everything parse() checks, plus the rules a skill must meet before writing (F§2, F§3):
 * required sections, block placement, a trace token on every prose line, and traces that
 * point to answered, non-superseded questions.
 * @param {string} body
 * @param {{type?: 'feature'|'bug'|'unknown'}} opts  type 'bug' or 'unknown' requires "Bug details"
 */
function lint(body, { type } = {}) {
  const p = parse(body);
  const { lines, blocks } = p;
  const fenced = fenceMask(lines);
  const errors = [...(isManaged(body) ? [] : [`missing ${FORMAT_MARKER} marker`]), ...p.errors];

  const required = [...BASE_SECTIONS, ...(type === 'bug' || type === 'unknown' ? ['Bug details'] : [])];
  for (const s of required) if (!sectionRange(lines, s)) errors.push(`missing section "## ${s}"`);

  for (const b of blocks.values()) {
    const r = sectionRange(lines, SECTIONS[b.status]);
    if (r && !(b.start > r.head && b.end < r.end)) {
      errors.push(`${b.id} has status ${b.status} but is not inside "## ${SECTIONS[b.status]}"`);
    }
  }

  for (const s of PROSE_SECTIONS) {
    const r = sectionRange(lines, s);
    if (!r) continue;
    for (let i = r.head + 1; i < r.end; i += 1) {
      const t = lines[i].trim();
      if (fenced[i] || !t || t.startsWith('#') || /^\*\*[^*]+\*\*$/.test(t) || /^_None[^_]*_$/.test(t)) continue;
      const pending = [...t.matchAll(PENDING_RE)].map((m) => m[1]);
      const traces = [...t.matchAll(TRACE_RE)].map((m) => m[1]);
      if (!pending.length && !traces.length) {
        errors.push(`line ${i + 1} ("${s}") has no trace token: "${t.slice(0, 70)}"`);
        continue;
      }
      for (const id of traces.filter((x) => /^Q\d+$/.test(x))) {
        const b = blocks.get(id);
        if (!b) errors.push(`line ${i + 1}: traced to unknown question ${id}`);
        else if (b.status !== 'answered') errors.push(`line ${i + 1}: traced to ${id}, which is ${b.status} — write _pending ${id}_ instead`);
        else if (b.superseded) errors.push(`line ${i + 1}: traced to ${id}, which is superseded by ${b.superseded}`);
      }
      for (const id of pending) if (!blocks.has(id)) errors.push(`line ${i + 1}: _pending ${id}_ refers to an unknown question`);
    }
  }

  const pendingAll = [...body.matchAll(PENDING_RE)].map((m) => m[1]);
  const ids = [...blocks.keys()];
  const byStatus = (st) => ids.filter((id) => blocks.get(id).status === st);
  if (body.length > 65536) errors.push(`body is ${body.length} characters; GitHub allows 65536`);
  return {
    ok: errors.length === 0,
    errors,
    open: byStatus('open'),
    answered: byStatus('answered'),
    obsolete: byStatus('obsolete'),
    superseded: ids.filter((id) => blocks.get(id).superseded),
    nextId: `Q${Math.max(0, ...ids.map(idNum)) + 1}`,
    // answered/obsolete questions that the prose still marks as _pending_ → fold before Ready
    pendingToFold: [...new Set(pendingAll.filter((id) => blocks.get(id) && blocks.get(id).status !== 'open'))],
    length: body.length,
  };
}

module.exports = {
  FORMAT_MARKER,
  lint,
  vanishedIds,
  NONE,
  SECTIONS,
  isManaged,
  parse,
  countOpen,
  sanitize,
  parseCommands,
  applyCommands,
};
