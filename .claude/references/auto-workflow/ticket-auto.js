export const meta = {
  name: 'ticket-auto',
  description: 'The /ticket:auto loop: implement, review and hand off a milestone ticket by ticket, parking what blocks',
  whenToUse: 'Launched by /ticket:auto after its preflight and start gate, never on its own',
  phases: [
    { title: 'Pick', detail: 'checkpoint, then claim the next eligible ticket (or resume one)' },
    { title: 'Plan', detail: 'a fresh implementer plans; challenger and plan advisors attack it' },
    { title: 'Implement', detail: 'a fresh implementer builds or fixes on the ticket branch' },
    { title: 'Review', detail: 'the suite, then blocking and advisory agents, then the evaluation' },
    { title: 'Hand off', detail: 'sign-off and review stage (or close), or park' },
  ],
}

// The ticket loop of .claude/commands/ticket/auto.md § Step 1, as deterministic
// control flow. The script decides; agents act. Bookkeeping agents follow
// .claude/references/auto-workflow/clerk.md (engine transitions, git, the
// suite, run.log); the implementer follows .claude/references/auto/implementer.md;
// the review agents are dispatched by name. Nothing here asks the user: a
// question an attended run needs comes back as `ask`, the session gates it and
// relaunches with a `resume` entry.
//
// args (built by the session at preflight — auto.md § Step 1 on Claude Code):
//   milestone, base, until (ISO deadline or null), onDone ('review'|'close'),
//   attended (bool), maxRounds, maxTickets, handledSoFar,
//   reviewAgents, advisors, planAdvisors (resolved, missing files dropped),
//   resume: [{ id, title, branch, phase: 'plan'|'implement'|'review', plan?, answer? }]

const A = args || {}
const CLERK = '.claude/references/auto-workflow/clerk.md'
const BRIEF = '.claude/references/auto/implementer.md'
const MAX_ROUNDS = A.maxRounds || 3
const MAX_TICKETS = A.maxTickets || 0
const ATTENDED = !!A.attended
const BLOCKING = A.reviewAgents && A.reviewAgents.length ? A.reviewAgents : ['code-reviewer', 'test-adequacy-reviewer']
const ADVISORY = ['code-challenger', 'code-simplifier'].concat(A.advisors || [])
const PLAN_AGENTS = ['challenger'].concat(A.planAdvisors || [])
const RUN = [
  `MILESTONE: ${A.milestone || '--all'}`,
  `BASE: ${A.base}`,
  `UNTIL: ${A.until || 'none'}`,
  `ON_DONE: ${A.onDone || 'review'}`,
  `ATTENDED: ${ATTENDED ? 'yes' : 'no'}`,
].join('\n')

const str = { type: 'string' }
const strs = { type: 'array', items: str }
const bool = { type: 'boolean' }

const PICK = {
  type: 'object',
  properties: { stop: bool, halt: bool, found: bool, reason: str, id: str, title: str, branch: str, diff_base: str },
  required: ['stop', 'halt', 'found', 'reason', 'id', 'title', 'branch', 'diff_base'],
}
const SUITE = {
  type: 'object',
  properties: { stop: bool, infra: bool, clean: bool, green: bool, reason: str, head: str, diff_base: str, failures: str },
  required: ['stop', 'infra', 'clean', 'green', 'reason', 'head', 'diff_base', 'failures'],
}
const IMPL = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['PLAN', 'DONE', 'BLOCKED'] },
    blocked_kind: { type: 'string', enum: ['none', 'needs-owner', 'infra', 'other'] },
    reason: str, question: str, options: strs,
    what_changes: str, plan: str,
    commits: strs, what_landed: strs, tests: strs, evidence: str, disputed: strs, followups: strs,
  },
  required: ['status', 'blocked_kind', 'reason'],
}
const EVAL = {
  type: 'object',
  properties: {
    recheck: { type: 'array', items: { type: 'object', properties: { agent: str, failed: str }, required: ['agent', 'failed'] } },
    decision: { type: 'string', enum: ['pending', 'approve', 'revise', 'contested', 'done', 'iterate', 'replan', 'escalate'] },
    worklist: strs, open_findings: strs, carried: strs, followups: strs, verdicts: str, record: str,
  },
  required: ['recheck', 'decision', 'worklist', 'open_findings', 'carried', 'followups', 'verdicts', 'record'],
}
const DONE = {
  type: 'object',
  properties: { ok: bool, result: { type: 'string', enum: ['review', 'closed', 'close-held', 'parked', 'halt'] }, reason: str },
  required: ['ok', 'result', 'reason'],
}

const out = { handedOff: [], parked: [], left: [], halted: null, stopped: null, sessionLimit: false, ask: null, handled: 0 }
let handled = A.handledSoFar || 0
const skip = []
const queue = (A.resume || []).slice()

const lines = xs => (xs && xs.length ? xs.map(x => `- ${x}`).join('\n') : 'none')

function clerk(op, input, phaseName, schema, id) {
  return agent(`Read ${CLERK} and run operation \`${op}\`, then return its structured result.\n\n${RUN}\n\n${input}`,
    { label: `clerk:${op}${id ? ':' + id : ''}`, phase: phaseName, schema })
}

function implementer(t, mode, extra) {
  return agent([
    `Read ${BRIEF} and follow it.`, '',
    `MODE: ${mode}`, `TICKET: ${t.id}`, `BRANCH: ${t.branch}`, `BASE: ${t.diff_base}`, '',
    extra || '', '',
    'You are a fresh implementer: anything earlier implementers did is in the ticket and in `git log BASE..BRANCH`.',
    "Return your report as the structured output — `status` is the brief's first-line status, `blocked_kind` says which BLOCKED it is (`none` otherwise), the other fields are the brief's report fields.",
    `Before you finish, append one line to .ticket-auto/run.log: \`<ISO time> ${t.id} implement ${mode} <status>\`.`,
  ].join('\n'), { label: `implement:${t.id}:${mode}`, phase: mode === 'plan' ? 'Plan' : 'Implement', schema: IMPL })
}

async function dispatch(names, prompt, phaseName, t) {
  const replies = await parallel(names.map(n => () => agent(prompt, { agentType: n, label: `${n}:${t.id}`, phase: phaseName })))
  return names.map((n, i) => ({ agent: n, prompt, reply: replies[i] }))
}

function evalPrompt(op, t, results, ctx, final) {
  const body = results.map(r => `=== REPLY ${r.agent} ===\n${r.reply == null ? '(the agent died without a reply)' : r.reply}\n=== END ${r.agent} ===`).join('\n\n')
  return `TICKET: ${t.id}\nBRANCH: ${t.branch}\nBASE: ${t.diff_base}\nFINAL: ${final ? 'yes' : 'no'}\n${ctx}\n\n${body}`
}

// Reply-check, re-ask each failing agent once, then evaluate on the final set.
async function evaluate(op, t, results, ctx, phaseName) {
  let ev = await clerk(op, evalPrompt(op, t, results, ctx, false), phaseName, EVAL, t.id)
  if (!ev || !ev.recheck.length) return ev
  const again = await parallel(ev.recheck.map(rc => () => {
    const orig = results.find(r => r.agent === rc.agent)
    return agent(`${orig ? orig.prompt : ''}\n\nYour previous reply failed the output-contract check: ${rc.failed}\nReply again, following your output contract exactly.`,
      { agentType: rc.agent, label: `${rc.agent}:${t.id}:recheck`, phase: phaseName })
  }))
  ev.recheck.forEach((rc, i) => {
    const r = results.find(x => x.agent === rc.agent)
    if (r) r.reply = again[i]
  })
  return clerk(op, evalPrompt(op, t, results, ctx, true), phaseName, EVAL, t.id)
}

const halt = reason => ({ kind: 'halt', reason })
const park = (reason, round) => ({ kind: 'park', reason, round: round || 0 })

// An implementer report → null to go on, or the ticket's outcome.
function judgeReport(t, r, mode, plan) {
  if (!r) return halt(`infra: implementer (${mode}) on ${t.id} died without a report`)
  if (r.status === 'BLOCKED') {
    if (r.blocked_kind === 'infra') return halt(`infra: ${r.reason}`)
    if (r.blocked_kind === 'needs-owner') {
      if (!ATTENDED) return park(`needs owner: ${r.question || r.reason}`)
      return { kind: 'ask', ask: {
        kind: 'owner', id: t.id, title: t.title, branch: t.branch, question: r.question || r.reason,
        options: r.options || [], resumePhase: mode === 'plan' ? 'plan' : mode === 'implement' ? 'implement' : 'review', plan,
      } }
    }
    return park(r.reason)
  }
  if (mode === 'plan' && r.status !== 'PLAN') return park(`implementer reported ${r.status} in plan mode`)
  if (mode !== 'plan' && r.status !== 'DONE') return park(`implementer reported ${r.status} in ${mode} mode`)
  return null
}

const planOf = r => `What this changes: ${r.what_changes || ''}\n\nPlan:\n${r.plan || ''}`

async function runTicket(t, entry) {
  let start = entry ? entry.phase : 'plan'
  let plan = (entry && entry.plan) || ''
  let answer = entry && entry.answer ? `OWNER DECISION (recorded on the ticket under ## Owner decision): ${entry.answer}` : ''
  let challenges = ''
  let report = null
  const records = []
  const followups = []

  if (start === 'plan') {
    let r = await implementer(t, 'plan', answer)
    let o = judgeReport(t, r, 'plan', plan)
    if (o) return o
    followups.push(...(r.followups || []))
    plan = planOf(r)
    for (let attempt = 1; ; attempt++) {
      const prompt = `Challenge the drafted plan for ticket ${t.id} (read it with \`.claude/scripts/te read ${t.id}\`, including ## Decisions & assumptions and ## Non-functional requirements).\nDiff base: ${t.diff_base}; the ticket branch ${t.branch} is checked out.\n\n${plan}`
      const results = await dispatch(PLAN_AGENTS, prompt, 'Plan', t)
      const ev = await evaluate('evaluate-plan', t, results, `ATTEMPT: ${attempt} of 2\n\n${plan}`, 'Plan')
      if (!ev) return halt('infra: plan evaluation died')
      challenges = results.map(x => `=== ${x.agent} ===\n${x.reply || '(no reply)'}`).join('\n\n')
      records.push(`Plan: ${ev.verdicts} → ${ev.decision}`)
      followups.push(...ev.followups)
      if (ev.decision === 'approve') break
      if (ev.decision === 'revise' && attempt === 1) {
        r = await implementer(t, 'plan', `${answer}\n\nYOUR PREVIOUS PLAN:\n${plan}\n\nCHALLENGE REPORTS — revise the plan, or rebut a point with evidence (file:line):\n${challenges}`)
        o = judgeReport(t, r, 'plan', plan)
        if (o) return o
        plan = planOf(r)
        continue
      }
      const why = ev.open_findings.join('; ')
      if (!ATTENDED) return park(`plan contested: ${why}`)
      return { kind: 'ask', ask: {
        kind: 'plan', id: t.id, title: t.title, branch: t.branch,
        question: `Plan for ${t.id} is contested: ${why}. Proceed?`,
        options: ['Park (Recommended)', 'Approve as revised'], resumePhase: 'implement', plan,
      } }
    }
    start = 'implement'
    answer = ''
  }

  if (start === 'implement') {
    const r = await implementer(t, 'implement', `APPROVED PLAN:\n${plan}\n\n${answer}\n\nCHALLENGE REPORTS (weigh the WEAKNESSES; adopt what is sound):\n${challenges || 'none'}`)
    const o = judgeReport(t, r, 'implement', plan)
    if (o) return o
    report = r
    followups.push(...(r.followups || []))
    answer = ''
  }

  let prior = 'none'
  let changed = 'none'
  let disputed = 'none'
  let carried = []
  let resumeMode = start === 'review'
  for (let n = 1; n <= MAX_ROUNDS; n++) {
    let s = await clerk('suite', `TICKET: ${t.id}\nBRANCH: ${t.branch}\nROUND: ${n}`, 'Review', SUITE, t.id)
    if (!s) return halt('infra: suite agent died')
    if (s.stop) return { kind: 'stop', reason: s.reason, round: n }
    if (s.infra) return halt(`infra: ${s.reason}`)
    if (!s.clean) {
      const r = await implementer(t, 'fix', 'WORK-LIST:\n- commit or revert your uncommitted edits, then report')
      const o = judgeReport(t, r, 'fix', plan)
      if (o) return o
      s = await clerk('suite', `TICKET: ${t.id}\nBRANCH: ${t.branch}\nROUND: ${n}`, 'Review', SUITE, t.id)
      if (!s || s.infra) return halt(`infra: ${s ? s.reason : 'suite agent died'}`)
      if (s.stop) return { kind: 'stop', reason: s.reason, round: n }
      if (!s.clean) return park('the implementer left the tree dirty twice', n)
    }
    t.diff_base = s.diff_base || t.diff_base

    let worklist
    if (!s.green) {
      records.push(`R${n}: suite red → iterate`)
      if (n === MAX_ROUNDS) return park(`suite still red after ${n} round(s):\n${s.failures}`, n)
      worklist = [`failing tests (fix them; never dispute a failing test):\n${s.failures}`]
    } else {
      const prompt = [
        `Review ticket ${t.id} (read it with \`.claude/scripts/te read ${t.id}\`: acceptance criteria, and every ## Non-functional requirements line as an acceptance criterion).`,
        `The ticket branch ${t.branch} is checked out; diff base ${t.diff_base}; head ${s.head}. The test commands are verification.test_commands in .claude/config.yaml — the suite is green on this head.`,
        `Round ${n} of ${MAX_ROUNDS}.`, '',
        `APPROVED PLAN:\n${plan || '(not recorded — this ticket resumed after an interrupted run; judge against the ticket)'}`, '',
        `PRIOR FINDINGS:\n${prior}`, '', `WHAT CHANGED SINCE:\n${changed}`, '', `DISPUTED BY THE IMPLEMENTER:\n${disputed}`,
      ].join('\n')
      const results = await dispatch(BLOCKING.concat(ADVISORY), prompt, 'Review', t)
      const ev = await evaluate('evaluate-round', t, results, [
        `ROUND: ${n} of ${MAX_ROUNDS}`, `BLOCKING: ${BLOCKING.join(', ')}`, `ADVISORY: ${ADVISORY.join(', ')}`,
        `SUITE: green on ${s.head}`, '', `APPROVED PLAN:\n${plan || '(not recorded)'}`, '', `PRIOR FINDINGS:\n${prior}`, '', `DISPUTED:\n${disputed}`,
      ].join('\n'), 'Review')
      if (!ev) return halt('infra: round evaluation died')
      records.push(`R${n}: ${ev.verdicts} → ${ev.decision} — ${ev.record}`)
      followups.push(...ev.followups)
      carried = ev.carried
      if (ev.decision === 'done') {
        const h = await clerk('handoff', [
          `TICKET: ${t.id}\nTITLE: ${t.title}\nBRANCH: ${t.branch}\nHEAD: ${s.head}\nROUNDS: ${n}`, '',
          `PLAN:\n${plan || '(not recorded — summarise from the ticket and the branch log)'}`, '',
          `WHAT LANDED:\n${lines(report && report.what_landed)}`, '', `TESTS:\n${lines(report && report.tests)}`, '',
          `EVIDENCE:\n${(report && report.evidence) || 'none'}`, '', `LOOP LOG:\n${lines(records)}`, '',
          `CARRIED ADVISORY:\n${lines(carried)}`, '', `FOLLOWUPS:\n${lines(followups)}`,
        ].join('\n'), 'Hand off', DONE, t.id)
        if (!h) return halt('infra: handoff agent died')
        if (h.result === 'halt') return halt(h.reason)
        return { kind: 'handed', result: h.result, reason: h.reason, rounds: n }
      }
      if (ev.decision === 'replan') return park(`plan wrong:\n${lines(ev.open_findings)}`, n)
      if (ev.decision === 'escalate') return park(`open after ${n} round(s):\n${lines(ev.open_findings)}`, n)
      if (n === MAX_ROUNDS) return park(`round cap reached with findings open:\n${lines(ev.open_findings)}`, n)
      worklist = ev.worklist
      prior = lines(ev.open_findings)
    }

    const mode = resumeMode ? 'resume' : 'fix'
    resumeMode = false
    const r = await implementer(t, mode, `APPROVED PLAN:\n${plan || '(not recorded — read the ticket and git log BASE..BRANCH)'}\n\n${answer}\n\nWORK-LIST:\n${lines(worklist)}`)
    answer = ''
    const o = judgeReport(t, r, mode, plan)
    if (o) return o
    report = r
    followups.push(...(r.followups || []))
    changed = lines(r.what_landed)
    disputed = lines(r.disputed)
  }
  return park('round cap reached', MAX_ROUNDS)
}

while (!out.halted && !out.stopped && !out.ask) {
  const entry = queue.shift() || null
  if (!entry && MAX_TICKETS && handled >= MAX_TICKETS) {
    const peek = await clerk('pick', `PEEK: yes\nHANDLED: ${handled}\nSKIP: ${skip.join(', ') || 'none'}`, 'Pick', PICK)
    if (peek && peek.found) out.sessionLimit = true
    break
  }
  const p = await clerk('pick', entry ? `RESUME: ${entry.id} ${entry.branch}` : `SKIP: ${skip.join(', ') || 'none'}`, 'Pick', PICK)
  if (!p) { out.halted = 'infra: pick agent died'; break }
  if (p.stop) { out.stopped = p.reason; if (entry) out.left.push({ id: entry.id, title: entry.title, branch: entry.branch, round: 0 }); break }
  if (p.halt) { out.halted = p.reason; break }
  if (!p.found) break

  const t = { id: p.id, title: p.title, branch: p.branch, diff_base: p.diff_base }
  log(`${t.id} — ${t.title}`)
  const res = await runTicket(t, entry)
  if (res.kind === 'handed') {
    out.handedOff.push({ id: t.id, title: t.title, branch: t.branch, result: res.result, reason: res.reason, rounds: res.rounds })
    handled++
    log(`${t.id} handed off: ${res.result}`)
  } else if (res.kind === 'park') {
    const k = await clerk('park', `TICKET: ${t.id}\nBRANCH: ${t.branch}\nROUND: ${res.round}\nREASON:\n${res.reason}`, 'Hand off', DONE, t.id)
    if (!k || !k.ok) { out.halted = `park failed for ${t.id}: ${k ? k.reason : 'agent died'}`; out.left.push({ id: t.id, title: t.title, branch: t.branch, round: res.round }); break }
    out.parked.push({ id: t.id, title: t.title, branch: t.branch, reason: res.reason })
    skip.push(t.id)
    handled++
    log(`${t.id} parked`)
  } else if (res.kind === 'ask') {
    out.ask = res.ask
    out.left.push({ id: t.id, title: t.title, branch: t.branch, round: 0 })
  } else if (res.kind === 'stop') {
    out.stopped = res.reason
    out.left.push({ id: t.id, title: t.title, branch: t.branch, round: res.round })
  } else {
    out.halted = res.reason
    out.left.push({ id: t.id, title: t.title, branch: t.branch, round: 0 })
  }
}

out.handled = handled
return out
