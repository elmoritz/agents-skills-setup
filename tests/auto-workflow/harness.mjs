// Offline control-flow test for .claude/references/auto-workflow/ticket-auto.js.
// Runs the workflow script against scripted agents (no model, no tokens) and
// asserts each scenario's outcome and the agents it dispatched. The script's
// agents are routed by label: clerk:<op>[:id], implement:<id>:<mode>, and
// review agents by agentType.
import { readFileSync } from 'node:fs'

const SCRIPT = process.argv[2] || '.claude/references/auto-workflow/ticket-auto.js'
const src = readFileSync(SCRIPT, 'utf8')
if (!/^export const meta = \{/.test(src)) throw new Error('script must begin with `export const meta = {`')
for (const banned of ['Date.now(', 'Math.random(', 'new Date()']) {
  if (src.includes(banned)) throw new Error(`script uses ${banned}, which the Workflow runtime forbids`)
}
const body = src.replace(/^export const meta =/, 'const meta =')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const run = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', 'budget', body)

const T = (id) => ({ stop: false, halt: false, found: true, reason: '', id, title: `title ${id}`, branch: `ticket/${id}-x`, diff_base: 'b0' })
const NONE = { stop: false, halt: false, found: false, reason: '', id: '', title: '', branch: '', diff_base: '' }
const GREEN = { stop: false, infra: false, clean: true, green: true, reason: '', head: 'h1', diff_base: 'b0', failures: '' }
const RED = { ...GREEN, green: false, failures: 'FooTest.bar failed' }
const ev = (decision, extra = {}) => ({ recheck: [], decision, worklist: ['fix x'], open_findings: ['finding'], carried: [], followups: [], verdicts: 'v', record: 'r', ...extra })
const impl = (status, extra = {}) => ({ status, blocked_kind: 'none', reason: '', question: '', options: [], what_changes: 'c', plan: '1. step', what_landed: ['a.js — x'], tests: ['t → 0'], followups: [], disputed: [], ...extra })

// h: per-role handlers; each gets (prompt, nthCallOfThatRole).
async function scenario(name, h, args, check) {
  const calls = []
  const n = {}
  const agent = async (prompt, opts = {}) => {
    const label = opts.label || ''
    const role = opts.agentType && !label.startsWith('clerk') && !label.startsWith('implement') ? 'reviewer'
      : label.split(':').slice(0, label.startsWith('implement') ? 3 : 2).join(':').replace(/^implement:[^:]+:/, 'implement:')
    n[role] = (n[role] || 0) + 1
    calls.push(opts.agentType && role === 'reviewer' ? `${opts.agentType}` : role)
    const f = h[role]
    if (!f) throw new Error(`${name}: no handler for ${role} (label ${label})`)
    return f(prompt, n[role], opts)
  }
  const parallel = async (thunks) => Promise.all(thunks.map(t => t().catch(() => null)))
  const out = await run(agent, parallel, null, () => {}, () => {}, args, { total: null, spent: () => 0, remaining: () => Infinity })
  try { check(out, calls) } catch (e) { console.log(`FAIL [${name}]: ${e.message}\n  calls: ${calls.join(' ')}\n  out: ${JSON.stringify(out)}`); return false }
  console.log(`  ok: ${name}`)
  return true
}
const eq = (a, b, what) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${what}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`) }
const count = (calls, x) => calls.filter(c => c === x).length

const base = {
  'clerk:pick': (_, k) => (k === 1 ? T('T-1') : NONE),
  'implement:plan': () => impl('PLAN'),
  'implement:implement': () => impl('DONE'),
  'implement:fix': () => impl('DONE'),
  'implement:resume': () => impl('DONE'),
  'clerk:suite': () => GREEN,
  'clerk:evaluate-plan': () => ev('approve'),
  'clerk:evaluate-round': () => ev('done'),
  'clerk:handoff': () => ({ ok: true, result: 'review', reason: '' }),
  'clerk:park': () => ({ ok: true, result: 'parked', reason: '' }),
  reviewer: () => '**Verdict:** PASS',
}
const A = { base: 'main', milestone: 'v1', maxRounds: 3, attended: false }
const results = []

results.push(await scenario('happy path hands off to review', base, A, (o, c) => {
  eq(o.handedOff.map(x => [x.id, x.result, x.rounds]), [['T-1', 'review', 1]], 'handed off')
  eq(o.parked.length + o.left.length, 0, 'nothing parked or left')
  eq(count(c, 'challenger'), 1, 'challenger dispatched once')
  for (const a of ['code-reviewer', 'test-adequacy-reviewer', 'code-challenger', 'code-simplifier']) eq(count(c, a), 1, `${a} dispatched`)
  eq(o.handled, 1, 'handled')
}))

results.push(await scenario('configured agents join the defaults', base,
  { ...A, reviewAgents: ['code-reviewer', 'sql-checker'], advisors: ['perf-advisor'], planAdvisors: ['api-advisor'] }, (o, c) => {
    for (const a of ['sql-checker', 'perf-advisor', 'api-advisor', 'code-challenger']) eq(count(c, a), 1, `${a} dispatched`)
    eq(count(c, 'test-adequacy-reviewer'), 0, 'review.agents replaces the default blocking set')
  }))

results.push(await scenario('iterate to the cap parks with findings', { ...base, 'clerk:evaluate-round': () => ev('iterate') }, A, (o, c) => {
  eq(o.parked.map(x => x.id), ['T-1'], 'parked')
  eq(count(c, 'implement:fix'), 2, 'fix rounds between three reviews')
  eq(count(c, 'clerk:evaluate-round'), 3, 'three evaluations')
  eq(count(c, 'clerk:park'), 1, 'park op ran')
}))

results.push(await scenario('red suite skips agents, then green round hands off',
  { ...base, 'clerk:suite': (_, k) => (k === 1 ? RED : GREEN) }, A, (o, c) => {
    eq(o.handedOff.map(x => x.rounds), [2], 'handed off in round 2')
    eq(count(c, 'code-reviewer'), 1, 'reviewers only on the green round')
    eq(count(c, 'implement:fix'), 1, 'one fix for the red round')
  }))

results.push(await scenario('red suite on the last round parks', { ...base, 'clerk:suite': () => RED }, { ...A, maxRounds: 2 }, (o, c) => {
  eq(o.parked.length, 1, 'parked')
  eq(count(c, 'code-reviewer'), 0, 'agents never review a red diff')
}))

results.push(await scenario('re-plan parks immediately', { ...base, 'clerk:evaluate-round': () => ev('replan') }, A, (o, c) => {
  eq(o.parked.length, 1, 'parked'); eq(count(c, 'implement:fix'), 0, 'no fix after re-plan')
}))

results.push(await scenario('implementer infra halts and leaves the ticket for resume',
  { ...base, 'implement:implement': () => impl('BLOCKED', { blocked_kind: 'infra', reason: 'no toolchain' }) }, A, (o, c) => {
    eq(o.halted, 'infra: no toolchain', 'halted'); eq(o.left.map(x => x.id), ['T-1'], 'left for resume')
    eq(count(c, 'clerk:park'), 0, 'never parked for infra')
  }))

results.push(await scenario('implementer dying without a report halts', { ...base, 'implement:plan': () => null }, A, (o) => {
  if (!o.halted || !o.halted.startsWith('infra:')) throw new Error(`halted: ${o.halted}`)
}))

const owner = { ...base, 'implement:plan': () => impl('BLOCKED', { blocked_kind: 'needs-owner', question: 'Q?', options: ['a', 'b'] }) }
results.push(await scenario('owner question parks when unattended', owner, A, (o) => {
  eq(o.parked.map(x => x.reason), ['needs owner: Q?'], 'parked with the question'); eq(o.ask, null, 'no ask')
}))
results.push(await scenario('owner question returns ask when attended', owner, { ...A, attended: true }, (o, c) => {
  eq([o.ask.kind, o.ask.id, o.ask.question, o.ask.resumePhase], ['owner', 'T-1', 'Q?', 'plan'], 'ask')
  eq(o.left.map(x => x.id), ['T-1'], 'left claimed'); eq(count(c, 'clerk:park'), 0, 'not parked')
}))

const contested = { ...base, 'clerk:evaluate-plan': (_, k) => ev(k === 1 ? 'revise' : 'contested') }
results.push(await scenario('contested plan: one revision, then park unattended', contested, A, (o, c) => {
  eq(count(c, 'implement:plan'), 2, 'one revision'); eq(count(c, 'challenger'), 2, 'challenge re-run')
  eq(o.parked.length, 1, 'parked'); eq(count(c, 'implement:implement'), 0, 'never implemented')
}))
results.push(await scenario('contested plan asks when attended', contested, { ...A, attended: true }, (o) => {
  eq([o.ask.kind, o.ask.resumePhase], ['plan', 'implement'], 'plan ask resumes at implement')
}))
results.push(await scenario('revised plan approved goes on', { ...base, 'clerk:evaluate-plan': (_, k) => ev(k === 1 ? 'revise' : 'approve') }, A, (o) => {
  eq(o.handedOff.length, 1, 'handed off')
}))

results.push(await scenario('failed reply check re-asks once, then evaluates FINAL',
  { ...base, 'clerk:evaluate-round': (p, k) => (k === 1 ? ev('pending', { recheck: [{ agent: 'code-reviewer', failed: 'failed=no verdict' }] }) : (p.includes('FINAL: yes') ? ev('done') : ev('iterate'))) },
  A, (o, c) => {
    eq(count(c, 'code-reviewer'), 2, 're-asked once'); eq(count(c, 'clerk:evaluate-round'), 2, 'evaluated twice'); eq(o.handedOff.length, 1, 'handed off')
  }))

results.push(await scenario('checkpoint stop at pick ends the run', { ...base, 'clerk:pick': () => ({ ...NONE, stop: true, reason: 'STOP file' }) }, A, (o, c) => {
  eq(o.stopped, 'STOP file', 'stopped'); eq(count(c, 'implement:plan'), 0, 'nothing implemented')
}))
results.push(await scenario('checkpoint stop mid-ticket leaves it for resume', { ...base, 'clerk:suite': () => ({ ...GREEN, stop: true, reason: 'deadline' }) }, A, (o) => {
  eq([o.stopped, o.left.map(x => x.id)], ['deadline', ['T-1']], 'left')
}))

results.push(await scenario('session limit peeks and stops', { ...base, 'clerk:pick': (p, k) => (p.includes('PEEK') ? T('T-2') : k === 1 ? T('T-1') : T('T-9')) },
  { ...A, maxTickets: 1 }, (o, c) => {
    eq([o.sessionLimit, o.handled, o.handedOff.length], [true, 1, 1], 'limit'); eq(count(c, 'implement:plan'), 1, 'only one ticket run')
  }))
results.push(await scenario('session limit counts relaunches', { ...base, 'clerk:pick': (p) => (p.includes('PEEK') ? NONE : T('T-1')) },
  { ...A, maxTickets: 2, handledSoFar: 2 }, (o, c) => {
    eq([o.sessionLimit, count(c, 'implement:plan')], [false, 0], 'queue empty: no limit, nothing run')
  }))

results.push(await scenario('resume entry enters review round 1, first fix is MODE resume',
  { ...base, 'clerk:pick': (p, k) => (p.includes('RESUME: T-7') ? T('T-7') : NONE), 'clerk:evaluate-round': (_, k) => ev(k === 1 ? 'iterate' : 'done') },
  { ...A, resume: [{ id: 'T-7', title: 't', branch: 'ticket/T-7-x', phase: 'review' }] }, (o, c) => {
    eq(count(c, 'implement:plan') + count(c, 'implement:implement'), 0, 'no plan or implement')
    eq([count(c, 'implement:resume'), count(c, 'implement:fix')], [1, 0], 'resume mode first')
    eq(o.handedOff.map(x => x.id), ['T-7'], 'handed off')
  }))
results.push(await scenario('owner answer resumes at implement with the decision',
  { ...base, 'clerk:pick': (p) => (p.includes('RESUME') ? T('T-3') : NONE),
    'implement:implement': (p) => { if (!p.includes('OWNER DECISION') || !p.includes('the plan')) throw new Error('decision/plan not passed'); return impl('DONE') } },
  { ...A, resume: [{ id: 'T-3', title: 't', branch: 'b', phase: 'implement', plan: 'the plan', answer: 'use a' }] }, (o, c) => {
    eq(count(c, 'implement:plan'), 0, 'no re-plan'); eq(o.handedOff.length, 1, 'handed off')
  }))

results.push(await scenario('handoff half-state halts', { ...base, 'clerk:handoff': () => ({ ok: false, result: 'halt', reason: 'pre_close failed' }) }, A, (o) => {
  eq(o.halted, 'pre_close failed', 'halted')
}))
results.push(await scenario('two tickets run in sequence', { ...base, 'clerk:pick': (_, k) => (k <= 2 ? T(`T-${k}`) : NONE) }, A, (o) => {
  eq(o.handedOff.map(x => x.id), ['T-1', 'T-2'], 'both')
}))

const failed = results.filter(r => !r).length
console.log(failed ? `test-auto-workflow: ${failed} FAILED` : `test-auto-workflow: ok (${results.length} scenarios)`)
process.exit(failed ? 1 : 0)
