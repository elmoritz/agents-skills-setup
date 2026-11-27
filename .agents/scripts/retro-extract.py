#!/usr/bin/env python3
"""Measure how one milestone was built, for /ticket:retro.

Usage:
  retro-extract.py <milestone> [--since ISO] [--until ISO] [--out DIR] [--no-tickets]
                   [--claude-root DIR] [--codex-root DIR]
  retro-extract.py --hook        Claude Code SubagentStop hook: hook JSON on stdin
  retro-extract.py --self-test

Three dimensions, each from what this machine recorded:
  time    the auto loop's run.log (.ticket-auto/run.log in every checkout `git
          worktree list` names): claim -> hand-off per ticket, review rounds,
          suite seconds; the ticket-state history (git on filesystem, `gh` on
          github) for how long handed-off work waited for a human.
  tokens  Claude Code transcripts (~/.claude/projects/<checkout>*/, sessions,
          subagents and Workflow agents) and Codex rollouts (~/.codex/sessions,
          by cwd). Other assistants keep no transcript this script can read; the
          coverage block says so instead of guessing.
  humans  gates and owner questions the loop logged, parks and held closes,
          AskUserQuestion calls and how long each waited for an answer, typed
          prompts per session, rejects after a hand-off, review-stage waits.

Writes:
  docs/retros/<M>.metrics.json              committed: numbers only, no transcript paths
  .ticket-auto/retro/<M>/outliers.md        not committed: where to look, <file>:<line>

`tok_eq` is one comparable number per API call in input-token equivalents:
uncached input + 1.25 x cache write + 0.1 x cache read + 5 x output. A ratio, not a bill.
Standard library only; Python 3.9+.
"""
import collections
import datetime
import glob
import json
import os
import re
import statistics
import subprocess
import sys

BUNDLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TE = os.path.join(BUNDLE, "scripts", "te")
PEAK_CTX = 150_000       # an agent above this is an outlier
ORCH_CTX = 200_000       # an orchestrator above this is an outlier
REPEAT = 3               # the same command or file read this often in one agent
MAX_ERRORS = 60          # tool errors listed in outliers.md
LONG_WAIT = 30 * 60      # a gate that waited this long for an answer
ROLES = ("pickable", "in_progress", "review", "terminal")


# ---------------------------------------------------------------- small helpers

def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_usage():
    return {"calls": 0, "in": 0, "cw": 0, "cr": 0, "out": 0, "peak_ctx": 0}


def add_usage(acc, i, cw, cr, out):
    acc["calls"] += 1
    acc["in"] += i
    acc["cw"] += cw
    acc["cr"] += cr
    acc["out"] += out
    acc["peak_ctx"] = max(acc["peak_ctx"], i + cw + cr)
    return i + cw + cr


def tok_eq(u):
    return round(u["in"] + 1.25 * u["cw"] + 0.1 * u["cr"] + 5 * u["out"])


def median(xs):
    return round(statistics.median(xs)) if xs else 0


def entries(path):
    """(line number, object) for every JSON line that parses."""
    try:
        f = open(path, errors="replace")
    except OSError:
        return
    with f:
        for n, line in enumerate(f, 1):
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if isinstance(o, dict):
                yield n, o


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict) and isinstance(b.get("text"), str))
    return ""


def run(cmd, cwd=None, timeout=120):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        return p.stdout if p.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


# ---------------------------------------------------------------- config and tickets

def load_config(main):
    """Resolved config (`te config validate`), as a flat dict."""
    cfg = {}
    for line in run([TE, "config", "validate"], cwd=main).splitlines():
        k, sep, v = line.partition("=")
        if sep and not k.startswith("#"):
            cfg[k] = v
    return cfg


def id_matcher(cfg):
    """A function text -> ticket id or None, for this backend's id form."""
    if cfg.get("backend.type") == "github":
        rx = [re.compile(r"TICKET:\s*#?(\d+)\b"), re.compile(r"\b[Tt]icket\s+#?(\d+)\b"), re.compile(r"#(\d+)\b")]
        return lambda s: next(("#" + m.group(1) for r in rx for m in [r.search(s or "")] if m), None)
    prefix = re.escape(cfg.get("ticket_id.prefix", "")) or r"[A-Z][A-Z0-9]*"
    r = re.compile(r"\b(%s-\d+)\b" % prefix)
    return lambda s: (lambda m: m.group(1) if m else None)(r.search(s or ""))


def milestone_tickets(main, milestone):
    """id -> summary, for every ticket of the milestone in any role te can list."""
    out = {}
    for role in ROLES:
        block = {}
        for line in (run([TE, "list", role, "--milestone", milestone], cwd=main) + "\n\n").splitlines():
            if not line.strip():
                if block.get("id"):
                    block["role"] = role
                    out[block["id"]] = block
                block = {}
                continue
            k, _, v = line.partition("=")
            block[k] = v
    return out


def human_closes(main, cfg, ids):
    """id -> {closed, rejects[]}: when a human closed it, and every reject, from the ticket history."""
    out = {}
    if cfg.get("backend.type") == "github":
        for i in ids:
            raw = run(["gh", "issue", "view", i.lstrip("#"), "--json", "closedAt,state"], cwd=main)
            try:
                o = json.loads(raw) if raw else {}
            except ValueError:
                o = {}
            if o.get("closedAt"):
                out[i] = {"closed": ts(o["closedAt"]), "rejects": []}
        return out

    def pattern(template):
        if not template:
            return None
        rx = re.escape(template).replace(re.escape("{title}"), ".*").replace(re.escape("{id}"), "(?P<id>\\S+)")
        return re.compile("^" + rx)
    done, reject = pattern(cfg.get("commits.done")), pattern(cfg.get("commits.reject"))
    for line in run(["git", "log", "--all", "--format=%ct\t%s"], cwd=main).splitlines():
        t, _, subject = line.partition("\t")
        for kind, rx in (("closed", done), ("reject", reject)):
            m = rx.match(subject) if rx else None
            if m and m.group("id") in ids:
                row = out.setdefault(m.group("id"), {"closed": None, "rejects": []})
                if kind == "closed":
                    row["closed"] = max(row["closed"] or 0, int(t))
                else:
                    row["rejects"].append(int(t))
    return out


# ---------------------------------------------------------------- the loop's run.log

def parse_log(path):
    rows = []
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return rows
    for line in lines:
        p = line.split(" ", 3)
        if len(p) < 3:
            continue
        try:
            t = ts(p[0])
        except ValueError:
            continue
        rows.append({"t": t, "who": p[1], "event": p[2], "detail": p[3] if len(p) > 3 else ""})
    return rows


def loop_windows(rows, milestone):
    """[(start, end, rows)] for each `loop start` .. `loop end` that names the milestone."""
    out, cur = [], None
    for r in rows:
        if r["who"] == "loop" and r["event"] == "start":
            if cur:
                out.append(cur)
            cur = [r]
        elif cur is not None:
            cur.append(r)
            if r["who"] == "loop" and r["event"] == "end":
                out.append(cur)
                cur = None
    if cur:
        out.append(cur)
    word = re.compile(r"(^|\s)%s(\s|$)" % re.escape(milestone))
    return [(w[0]["t"], w[-1]["t"], w) for w in out if word.search(w[0]["detail"])]


def ticket_events(rows):
    """Per ticket: what the loop logged about it."""
    tickets = {}
    for r in rows:
        if r["who"] == "loop":
            continue
        t = tickets.setdefault(r["who"], {"first": r["t"], "last": r["t"], "rounds": [], "plan": None, "fixes": 0,
                                          "suite_s": 0, "suite_runs": 0, "red_runs": 0, "owner_questions": 0,
                                          "outcome": None, "notes": []})
        t["last"] = r["t"]
        e, d = r["event"], r["detail"]
        if e == "claim":
            t.setdefault("claimed", r["t"])
        elif e == "plan":
            t["plan"] = d
        elif e == "round":
            p = d.split(" ", 1)
            t["rounds"].append({"round": int(p[0]) if p[0].isdigit() else None,
                                "decision": d.rsplit("→", 1)[-1].strip() if "→" in d else "",
                                "verdicts": p[1].rsplit("→", 1)[0].strip() if len(p) > 1 else ""})
        elif e == "fix":
            t["fixes"] += 1
        elif e == "tests":
            p = d.split()
            t["suite_runs"] += 1
            if len(p) > 1 and p[1] != "0":
                t["red_runs"] += 1
            if len(p) > 2 and p[2].isdigit():
                t["suite_s"] += int(p[2])
        elif e == "owner":
            t["owner_questions"] += 1
            t["notes"].append("%s %s %s" % (iso(r["t"]), e, d))
        elif e == "gate":
            t["notes"].append("%s gate %s" % (iso(r["t"]), d))
        elif e == "handoff":
            t["outcome"] = "handoff-" + (d.split() or ["review"])[0]
            t["handed"] = r["t"]
        elif e == "parked":
            t["outcome"] = "parked"
            t["notes"].append("%s parked %s" % (iso(r["t"]), d))
        elif e in ("close-held", "halt", "resumed", "released", "stashed", "stop"):
            t["notes"].append("%s %s %s" % (iso(r["t"]), e, d))
    for t in tickets.values():
        t["wall_s"] = round(t["last"] - t["first"])
        if "claimed" in t and "handed" in t:
            t["claim_to_handoff_s"] = round(t["handed"] - t["claimed"])
    return tickets


def loop_humans(rows):
    """What the loop itself asked of a human."""
    gates = collections.Counter()
    out = {"gates": gates, "halts": [], "stops": 0, "session_limits": 0}
    for r in rows:
        if r["event"] == "gate":
            gates[(r["detail"].split() or ["?"])[0]] += 1
        if r["who"] != "loop":
            continue
        if r["event"] == "halt":
            out["halts"].append(r["detail"])
        elif r["event"] == "stop":
            out["stops"] += 1
        elif r["event"] == "session-limit":
            out["session_limits"] += 1
    out["gates"] = dict(gates)
    return out


# ---------------------------------------------------------------- Claude Code transcripts

def claude_blocks(o):
    c = (o.get("message") or {}).get("content")
    return c if isinstance(c, list) else []


def role_of(meta_type, prompt, description):
    p = prompt[:3000]
    if "references/auto/implementer.md" in p:
        return "implementer"
    if "auto-workflow/clerk.md" in p:
        return "clerk"
    return meta_type or "?"


def claude_agent(path, meta, find_id, pointers=False):
    """One subagent transcript -> its record (also what the hook stores)."""
    use = new_usage()
    seen, tools, cmds, reads = set(), collections.Counter(), collections.Counter(), collections.Counter()
    pending, errors, first, last, prompt, sleeps, branch = {}, [], None, None, "", 0, ""
    for n, o in entries(path):
        raw = o.get("timestamp")
        if raw:
            t = ts(raw)
            first = first or t
            last = t
        branch = branch or o.get("gitBranch") or ""
        kind = o.get("type")
        if kind == "assistant":
            msg = o.get("message") or {}
            mid = msg.get("id") or o.get("requestId") or o.get("uuid")
            if mid not in seen:
                seen.add(mid)
                u = msg.get("usage") or {}
                add_usage(use, u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0),
                          u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0))
            for b in claude_blocks(o):
                if b.get("type") != "tool_use":
                    continue
                name, inp = b.get("name", "?"), b.get("input") or {}
                tools[name] += 1
                label = name
                if name == "Bash":
                    cmd = " ".join(str(inp.get("command", "")).split())
                    cmds[cmd[:300]] += 1
                    sleeps += 1 if re.search(r"(^|[;&|]\s*)sleep \d", cmd) else 0
                    label = "Bash: " + cmd[:160]
                elif name == "Read":
                    reads[str(inp.get("file_path", ""))] += 1
                    label = "Read: " + str(inp.get("file_path", ""))
                pending[b.get("id")] = label
        elif kind == "user":
            c = (o.get("message") or {}).get("content")
            if not prompt and (isinstance(c, str) or not any(b.get("type") == "tool_result" for b in claude_blocks(o))):
                prompt = text_of(c)
            for b in claude_blocks(o):
                if b.get("type") == "tool_result" and b.get("is_error"):
                    errors.append({"line": n, "tool": pending.get(b.get("tool_use_id"), "?"),
                                   "error": " ".join(text_of(b.get("content")).split())[:300]})
    desc = meta.get("description", "")
    rec = {
        "assistant": "claude",
        "agent_id": os.path.basename(path)[len("agent-"):-len(".jsonl")],
        "type": role_of(meta.get("agentType"), prompt, desc),
        "workflow": os.path.basename(os.path.dirname(path)) if "/workflows/" in path else None,
        "description": desc[:120],
        "ticket": find_id(desc) or find_id(prompt[:800]) or find_id(branch),
        "start": iso(first) if first else None,
        "end": iso(last) if last else None,
        "wall_s": round(last - first) if first else 0,
        "tool_calls": sum(tools.values()),
        "tool_errors": len(errors),
        "sleeps": sleeps,
        "repeated_commands": sum(1 for v in cmds.values() if v >= REPEAT),
        "reread_files": sum(1 for v in reads.values() if v >= REPEAT),
        **use,
    }
    rec["tok_eq"] = tok_eq(rec)
    if pointers:
        rec["_errors"] = errors
        rec["_repeats"] = [(c, v) for c, v in cmds.most_common(5) if v >= REPEAT]
        rec["_rereads"] = [(f, v) for f, v in reads.most_common(5) if v >= REPEAT]
    return rec


def claude_session(path, in_loop, in_span, branch_ticket, calls_seen):
    """One main-session transcript -> its usage by bucket, and what it asked of a human."""
    buckets = collections.defaultdict(new_usage)
    ctx = collections.defaultdict(list)
    pending, errors, waits = {}, [], collections.Counter()
    asks, ask_wait, long_asks, prompts, compactions = 0, 0.0, [], 0, 0
    commands, first, last, runs_loop = collections.Counter(), None, None, False
    for n, o in entries(path):
        kind = o.get("type")
        raw = o.get("timestamp")
        if not raw:
            continue
        t = ts(raw)
        if kind == "user" and not runs_loop:
            runs_loop = bool(re.search(r"/?ticket[:-]auto\b", text_of((o.get("message") or {}).get("content"))[:2000]))
        ticket = branch_ticket(o.get("gitBranch") or "")
        if runs_loop and in_loop(t):
            bucket = "orchestrator"
        elif ticket:
            bucket = "attended:" + ticket
        elif in_span(t):
            bucket = "overhead:" + (o.get("gitBranch") or "?")
        else:
            continue
        first = first or t
        last = t
        if kind == "system" and o.get("subtype") == "compact_boundary":
            compactions += 1
        elif kind == "assistant":
            msg = o.get("message") or {}
            mid = msg.get("id") or o.get("requestId") or o.get("uuid")
            if mid not in calls_seen:
                calls_seen.add(mid)
                u = msg.get("usage") or {}
                ctx[bucket].append(add_usage(buckets[bucket], u.get("input_tokens", 0),
                                             u.get("cache_creation_input_tokens", 0),
                                             u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)))
            for b in claude_blocks(o):
                if b.get("type") == "tool_use":
                    pending[b.get("id")] = (b.get("name", "?"), t, n)
                    if b.get("name") == "AskUserQuestion":
                        asks += 1
        elif kind == "user":
            c = (o.get("message") or {}).get("content")
            results = [b for b in claude_blocks(o) if b.get("type") == "tool_result"]
            if not results and not o.get("isMeta"):
                prompts += 1
                for name in re.findall(r"<command-name>(/[\w:-]+)", c if isinstance(c, str) else text_of(c)):
                    commands[name] += 1
            for b in results:
                name, started, line = pending.pop(b.get("tool_use_id"), ("?", t, n))
                waits[name] += t - started
                if name == "AskUserQuestion":
                    ask_wait += t - started
                    if t - started >= LONG_WAIT:
                        long_asks.append({"line": line, "wait_s": round(t - started)})
                if b.get("is_error") and name != "AskUserQuestion":
                    errors.append({"line": n, "tool": name, "error": " ".join(text_of(b.get("content")).split())[:300]})
    if not buckets and not prompts:
        return None
    out = {"assistant": "claude", "session": os.path.basename(path)[:-len(".jsonl")],
           "start": iso(first) if first else None, "end": iso(last) if last else None,
           "compactions": compactions, "commands": dict(commands), "prompts": prompts,
           "asks": asks, "ask_wait_s": round(ask_wait),
           "tool_wait_s": {k: round(v) for k, v in waits.most_common() if v >= 60 and k != "AskUserQuestion"},
           "tool_errors": len(errors), "buckets": {}, "_errors": errors, "_long_asks": long_asks, "_path": path}
    for k, u in buckets.items():
        u["median_ctx"] = median(ctx[k])
        u["tok_eq"] = tok_eq(u)
        out["buckets"][k] = u
    return out


def claude_workflows(session_dir, in_span):
    out = []
    for p in sorted(glob.glob(os.path.join(session_dir, "workflows", "wf_*.json"))):
        try:
            o = json.load(open(p))
        except (OSError, ValueError):
            continue
        start = o.get("startTime") or o.get("timestamp")
        try:
            t = ts(start) if isinstance(start, str) else (start / 1000.0 if start else None)
        except (TypeError, ValueError):
            t = None
        if t is None or not in_span(t):
            continue
        out.append({"run": o.get("runId"), "name": o.get("workflowName"), "status": o.get("status"),
                    "agents": o.get("agentCount"), "wall_s": round((o.get("durationMs") or 0) / 1000),
                    "total_tokens": o.get("totalTokens"), "tool_calls": o.get("totalToolCalls")})
    return out


def claude_dirs(root, checkouts):
    """Every Claude Code project dir that belongs to one of the checkouts."""
    out = []
    for c in checkouts:
        slug = re.sub(r"[^A-Za-z0-9]", "-", c)
        out += [d for d in glob.glob(os.path.join(root, slug + "*"))
                if os.path.basename(d) == slug or os.path.basename(d).startswith(slug + "-")]
    return sorted(set(out))


# ---------------------------------------------------------------- Codex rollouts

def codex_rollout(path, checkouts, find_id):
    """One Codex rollout -> a session-like record when its cwd is one of the checkouts."""
    use, ctx, prev = new_usage(), [], None
    cwd, first, last, first_user, prompts, turns, calls, errors = None, None, None, "", 0, set(), 0, 0
    for n, o in entries(path):
        raw = o.get("timestamp")
        if raw:
            try:
                t = ts(raw)
            except ValueError:
                continue
            first = first or t
            last = t
        p = o.get("payload") or {}
        kind, ptype = o.get("type"), p.get("type")
        if kind in ("session_meta", "turn_context") and not cwd:
            cwd = p.get("cwd")
        elif kind == "event_msg" and ptype == "token_count" and p.get("info"):
            tot = (p["info"] or {}).get("total_token_usage") or {}
            cur = (tot.get("input_tokens", 0), tot.get("cached_input_tokens", 0),
                   tot.get("cache_write_input_tokens", 0), tot.get("output_tokens", 0))
            if prev is None or cur != prev:
                base = prev or (0, 0, 0, 0)
                d = [max(0, a - b) for a, b in zip(cur, base)]
                if any(d):
                    # OpenAI counts cached input inside input_tokens.
                    ctx.append(add_usage(use, max(0, d[0] - d[1]), d[2], d[1], d[3]))
                prev = cur
        elif kind == "event_msg" and ptype == "user_message":
            prompts += 1
            first_user = first_user or str(p.get("message", ""))
        elif kind == "event_msg" and ptype == "item_completed" and (p.get("item") or {}).get("type") == "UserMessage":
            if p.get("turn_id") not in turns:
                turns.add(p.get("turn_id"))
                first_user = first_user or text_of((p.get("item") or {}).get("content"))
        elif kind == "response_item" and ptype in ("function_call", "custom_tool_call"):
            calls += 1
        elif kind == "response_item" and ptype in ("function_call_output", "custom_tool_call_output"):
            out = str(p.get("output", ""))
            if re.search(r"Process exited with code [1-9]|\"exit_code\":\s*[1-9]", out[:400]):
                errors += 1
    if not cwd or not any(cwd == c or cwd.startswith(c + os.sep) for c in checkouts) or not use["calls"]:
        return None
    rec = {"assistant": "codex", "session": os.path.basename(path)[:-len(".jsonl")],
           "start": iso(first) if first else None, "end": iso(last) if last else None,
           "type": role_of(None, first_user, "") if role_of(None, first_user, "") != "?" else
           ("orchestrator" if re.search(r"ticket-auto\b", first_user[:2000]) else "session"),
           "ticket": find_id(first_user[:800]), "prompts": max(prompts, len(turns)),
           "tool_calls": calls, "tool_errors": errors, "wall_s": round(last - first) if first else 0, **use}
    rec["median_ctx"] = median(ctx)
    rec["tok_eq"] = tok_eq(rec)
    rec["_path"] = path
    return rec


# ---------------------------------------------------------------- the milestone

def main_checkout():
    common = run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]).strip()
    return os.path.dirname(common) if common else os.getcwd()


def worktrees(main):
    out = run(["git", "worktree", "list", "--porcelain"], cwd=main)
    return [line[len("worktree "):] for line in out.splitlines() if line.startswith("worktree ")] or [main]


def extract(milestone, main, checkouts, claude_root, codex_root, cfg, tickets, closes_fn,
            since=None, until=None):
    find_id = id_matcher(cfg)
    rows = sorted((r for c in checkouts for r in parse_log(os.path.join(c, ".ticket-auto", "run.log"))),
                  key=lambda r: r["t"])
    windows = loop_windows(rows, milestone)
    loop_rows = [r for _, _, w in windows for r in w]
    logged = ticket_events(loop_rows)
    ids = set(logged) | set(tickets)

    lo = ts(since) if since else min([w[0] for w in windows], default=None)
    hi = ts(until) if until else max([w[1] for w in windows], default=None)
    if lo is None or hi is None:
        raise SystemExit("retro-extract: no run.log window names %s; pass --since and --until" % milestone)

    def in_span(t):
        return lo <= t <= hi

    def in_loop(t):
        return any(a <= t <= b for a, b, _ in windows)

    prefix = cfg.get("git.branch_prefix", "ticket/")

    def branch_ticket(branch):
        if not branch.startswith(prefix):
            return None
        rest = branch[len(prefix):]
        hit = [i for i in ids if rest.startswith(i.lstrip("#") + "-") or rest == i.lstrip("#")]
        return max(hit, key=len) if hit else None

    sessions, agents, workflows, calls_seen = [], [], [], set()
    copies = collections.defaultdict(list)   # agent file name -> every copy (a resumed session keeps one too)
    for d in claude_dirs(claude_root, checkouts):
        for path in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            if os.path.getmtime(path) < lo - 86400:
                continue
            s = claude_session(path, in_loop, in_span, branch_ticket, calls_seen)
            if s:
                sessions.append(s)
            sdir = path[:-len(".jsonl")]
            workflows += claude_workflows(sdir, in_span)
            for ap in glob.glob(os.path.join(sdir, "subagents", "**", "agent-*.jsonl"), recursive=True):
                copies[os.path.basename(ap)].append(ap)
    for name in sorted(copies):
        # The copy with its .meta.json carries the agent type; among equals, the longest transcript.
        ap = max(copies[name], key=lambda p: (os.path.exists(p[:-len(".jsonl")] + ".meta.json"), os.path.getsize(p)))
        try:
            meta = json.load(open(ap[:-len(".jsonl")] + ".meta.json"))
        except (OSError, ValueError):
            meta = {}
        a = claude_agent(ap, meta, find_id, pointers=True)
        if not a["start"] or not (a["ticket"] in logged or in_span(ts(a["start"]))):
            continue
        a["in_loop"] = in_loop(ts(a["start"]))
        a["_path"] = ap
        agents.append(a)

    # Agents whose transcript is gone but whose record the hook kept.
    have = {a["agent_id"] for a in agents}
    main_hook = os.path.join(main, ".ticket-auto", "retro", "agents.jsonl")
    for _, a in entries(main_hook):
        if a.get("agent_id") in have or not a.get("start"):
            continue
        if a.get("ticket") in logged or in_span(ts(a["start"])):
            have.add(a["agent_id"])
            a["in_loop"] = in_loop(ts(a["start"]))
            a["source"] = "hook"
            agents.append(a)

    codex = []
    for path in sorted(glob.glob(os.path.join(codex_root, "**", "rollout-*.jsonl"), recursive=True)):
        if os.path.getmtime(path) < lo - 86400:
            continue
        r = codex_rollout(path, checkouts, find_id)
        if r and r["start"] and in_span(ts(r["start"])):
            codex.append(r)
    for r in codex:
        if r["type"] in ("orchestrator", "session"):
            sessions.append({"assistant": "codex", "session": r["session"], "start": r["start"], "end": r["end"],
                             "prompts": r["prompts"], "asks": None, "ask_wait_s": None, "compactions": None,
                             "commands": {}, "tool_wait_s": {}, "tool_errors": r["tool_errors"],
                             "buckets": {("orchestrator" if r["type"] == "orchestrator" and in_loop(ts(r["start"]))
                                          else ("attended:" + r["ticket"]) if r["ticket"] in ids
                                          else "overhead:codex"): {k: r[k] for k in
                                          ("calls", "in", "cw", "cr", "out", "peak_ctx", "median_ctx", "tok_eq")}},
                             "_errors": [], "_long_asks": [], "_path": r["_path"]})
        else:
            agents.append({**r, "agent_id": r["session"], "in_loop": in_loop(ts(r["start"])),
                           "sleeps": 0, "repeated_commands": 0, "reread_files": 0})

    # ---- tokens
    totals = collections.Counter()
    overhead = collections.Counter()
    for s in sessions:
        for k, u in s["buckets"].items():
            totals[k.split(":")[0]] += u["tok_eq"]
            if k.startswith("overhead:"):
                overhead[k[len("overhead:"):]] += u["tok_eq"]
    totals["agents"] = sum(a["tok_eq"] for a in agents)
    by_type = {}
    for name in sorted({a["type"] for a in agents}):
        g = [a for a in agents if a["type"] == name]
        eq = [a["tok_eq"] for a in g]
        by_type[name] = {"n": len(g), "calls": sum(a["calls"] for a in g), "tok_eq": sum(eq),
                         "median_tok_eq": median(eq), "max_tok_eq": max(eq),
                         "max_peak_ctx": max(a["peak_ctx"] for a in g), "wall_s": sum(a["wall_s"] for a in g),
                         "tool_calls": sum(a["tool_calls"] for a in g), "tool_errors": sum(a["tool_errors"] for a in g),
                         "sleeps": sum(a.get("sleeps", 0) for a in g)}

    # ---- humans: closes and rejects after a hand-off
    closes = closes_fn(sorted(ids))
    review_waits, rejects = [], 0
    per_ticket = {}
    for k in sorted(ids):
        mine = [a for a in agents if a["ticket"] == k]
        attended = sum(s["buckets"].get("attended:" + k, {}).get("tok_eq", 0) for s in sessions)
        if not mine and not attended and k not in logged:
            continue
        row = {f: v for f, v in logged.get(k, {}).items() if f not in ("first", "last", "claimed", "handed")}
        if k in tickets:
            row.update({f: tickets[k].get(f) for f in ("title", "type", "effort", "priority", "role")})
        c = closes.get(k) or {}
        handed = logged.get(k, {}).get("handed")
        if handed and logged[k]["outcome"] == "handoff-review":
            if c.get("closed") and c["closed"] >= handed:
                row["review_wait_s"] = round(c["closed"] - handed)
                review_waits.append(row["review_wait_s"])
            row["rejected_after_handoff"] = sum(1 for t in c.get("rejects", []) if t >= handed)
            rejects += row["rejected_after_handoff"]
        row["agents"] = dict(collections.Counter(a["type"] for a in mine))
        row["agent_tok_eq"] = sum(a["tok_eq"] for a in mine)
        row["attended_tok_eq"] = attended
        row["agent_tool_errors"] = sum(a["tool_errors"] for a in mine)
        per_ticket[k] = row

    handed = [t for t in logged.values() if (t["outcome"] or "").startswith("handoff")]
    claude_sessions = [s for s in sessions if s["assistant"] == "claude"]
    humans = loop_humans(loop_rows)
    humans.update({
        "owner_questions": sum(t["owner_questions"] for t in logged.values()),
        "parked": sum(1 for t in logged.values() if t["outcome"] == "parked"),
        "close_held": sum(1 for t in logged.values() for n in t["notes"] if " close-held " in n),
        "asks": sum(s["asks"] or 0 for s in claude_sessions),
        "ask_wait_s": sum(s["ask_wait_s"] or 0 for s in claude_sessions),
        "prompts": sum(s["prompts"] or 0 for s in sessions),
        "rejected_after_handoff": rejects,
        "review_wait_s": {"n": len(review_waits), "median": median(review_waits),
                          "max": max(review_waits) if review_waits else 0},
    })

    suite = [t["suite_s"] for t in logged.values()]
    lead = [t["claim_to_handoff_s"] for t in handed if "claim_to_handoff_s" in t]
    shipped_blind = sorted(k for k, t in logged.items() if (t["outcome"] or "").startswith("handoff")
                           and not any(a["ticket"] == k for a in agents))
    readers = ["claude"] + (["codex"] if codex else [])
    metrics = {
        "milestone": milestone,
        "span": {"start": iso(lo), "end": iso(hi), "hours": round((hi - lo) / 3600, 1)},
        "loop_windows": [{"start": iso(a), "end": iso(b), "hours": round((b - a) / 3600, 1)} for a, b, _ in windows],
        "coverage": {
            "transcript_readers": readers,
            "not_read": "Antigravity, Gemini CLI and Copilot keep no transcript this script reads: their tokens are not counted",
            "sessions": len(sessions), "agents": len(agents),
            "agents_from_hook_only": sum(1 for a in agents if a.get("source") == "hook"),
            "handed_off_without_agent_transcripts": shipped_blind,
            "rejects": "filesystem backend only" if cfg.get("backend.type") == "github" else "from git history",
        },
        "tokens": {"tok_eq_totals": dict(totals), "per_handed_off_ticket": round(sum(totals.values()) / len(handed)) if handed else None,
                   "agent_types": by_type, "overhead_by_branch": dict(overhead.most_common(12)),
                   "workflow_runs": workflows},
        "time": {"claim_to_handoff_s": {"n": len(lead), "median": median(lead), "max": max(lead) if lead else 0},
                 "suite_s": sum(suite), "suite_runs": sum(t["suite_runs"] for t in logged.values()),
                 "red_suite_runs": sum(t["red_runs"] for t in logged.values()),
                 "review_rounds": dict(collections.Counter(str(len(t["rounds"])) for t in logged.values() if t["rounds"]))},
        "humans": humans,
        "outcomes": dict(collections.Counter(t["outcome"] or "open" for t in logged.values())),
        "tickets": per_ticket,
        "sessions": [{k: v for k, v in s.items() if not k.startswith("_")} for s in sessions],
        "agents": [{k: v for k, v in a.items() if not k.startswith("_")} for a in sorted(agents, key=lambda a: a["start"] or "")],
    }
    return metrics, outliers(metrics, sessions, agents, logged)


def outliers(m, sessions, agents, logged):
    """Markdown: where to look, each with the evidence's place on disk."""
    o = ["# Outliers for %s" % m["milestone"], "",
         "Pointers are `<transcript>:<line>`: read a few lines around each, never the whole file.", ""]
    o += ["## Tickets that did not go straight through", ""]
    for k, t in sorted(logged.items()):
        if len(t["rounds"]) > 1 or t["notes"] or not (t["outcome"] or "").startswith("handoff"):
            rounds = "; ".join("R%s %s → %s" % (r["round"], r["verdicts"], r["decision"]) for r in t["rounds"])
            o.append("- %s: %s; %s; %d fix(es), %d red suite run(s), wall %dm" % (
                k, t["outcome"] or "open", rounds or "no rounds", t["fixes"], t["red_runs"], t["wall_s"] // 60))
            o += ["  - " + n for n in t["notes"]]
    o += ["", "## Waiting on a human", ""]
    for k, t in sorted(m["tickets"].items()):
        if t.get("review_wait_s", 0) >= 86400 or t.get("rejected_after_handoff"):
            o.append("- %s: waited %dh in review, rejected %d time(s) after the hand-off" % (
                k, t.get("review_wait_s", 0) // 3600, t.get("rejected_after_handoff", 0)))
    for s in sessions:
        for a in s.get("_long_asks", []):
            o.append("- a gate waited %dm for its answer -- %s:%d" % (a["wait_s"] // 60, s["_path"], a["line"]))
    o += ["", "## Agents far above their type", ""]
    for a in sorted(agents, key=lambda a: -a["tok_eq"]):
        med = m["tokens"]["agent_types"][a["type"]]
        if (med["n"] >= 4 and a["tok_eq"] > 1.5 * med["median_tok_eq"]) or a["peak_ctx"] > PEAK_CTX:
            o.append("- %s %s (%s): tok_eq %d against a median of %d, peak context %d, %d calls, %dm -- %s" % (
                a["type"], a["agent_id"], a["ticket"] or a.get("description", ""), a["tok_eq"], med["median_tok_eq"],
                a["peak_ctx"], a["calls"], a["wall_s"] // 60, a.get("_path", "transcript gone")))
    o += ["", "## Orchestrator sessions", ""]
    for s in sessions:
        peak = max([u["peak_ctx"] for u in s["buckets"].values()] or [0])
        if peak > ORCH_CTX or s.get("compactions"):
            o.append("- %s: peak context %d, %s compaction(s), waits %s -- %s" % (
                s["session"], peak, s.get("compactions"), s.get("tool_wait_s"), s["_path"]))
    o += ["", "## Repeated work inside one agent", ""]
    for a in agents:
        for cmd, n in a.get("_repeats", []):
            o.append("- %s %s (%s): %dx `%s` -- %s" % (a["type"], a["agent_id"], a["ticket"], n, cmd[:140], a["_path"]))
        for f, n in a.get("_rereads", []):
            o.append("- %s %s (%s): read %dx %s -- %s" % (a["type"], a["agent_id"], a["ticket"], n, f, a["_path"]))
        if a.get("sleeps", 0) >= REPEAT:
            o.append("- %s %s (%s): %d sleep polls" % (a["type"], a["agent_id"], a["ticket"], a["sleeps"]))
    o += ["", "## Tool errors", ""]
    errs = [(a["type"], a["ticket"], a["_path"], e) for a in agents for e in a.get("_errors", [])]
    errs += [("session", None, s["_path"], e) for s in sessions for e in s["_errors"]]
    for who, ticket, path, e in errs[:MAX_ERRORS]:
        o.append("- %s%s: `%s` -> %s -- %s:%d" % (who, " (%s)" % ticket if ticket else "", e["tool"][:120],
                                                  e["error"][:200], path, e["line"]))
    if len(errs) > MAX_ERRORS:
        o.append("- ... and %d more" % (len(errs) - MAX_ERRORS))
    return "\n".join(o) + "\n"


# ---------------------------------------------------------------- entry points

def hook():
    """SubagentStop: keep the agent's numbers, since transcripts are deleted after cleanupPeriodDays."""
    try:
        data = json.load(sys.stdin)
        path = data.get("agent_transcript_path")
        if not path or not os.path.exists(path):
            return 0
        try:
            meta = json.load(open(path[:-len(".jsonl")] + ".meta.json"))
        except (OSError, ValueError):
            meta = {}
        meta.setdefault("agentType", data.get("agent_type", "?"))
        main = main_checkout()
        rec = claude_agent(path, meta, id_matcher(load_config(main)))
        rec["session"] = data.get("session_id")
        out = os.path.join(main, ".ticket-auto", "retro")
        os.makedirs(out, exist_ok=True)
        if subprocess.run(["git", "check-ignore", "-q", ".ticket-auto/"], cwd=main).returncode != 0:
            exclude = run(["git", "rev-parse", "--git-path", "info/exclude"], cwd=main).strip()
            if exclude:
                exclude = exclude if os.path.isabs(exclude) else os.path.join(main, exclude)
                os.makedirs(os.path.dirname(exclude), exist_ok=True)
                with open(exclude, "a") as f:
                    f.write(".ticket-auto/\n")
        with open(os.path.join(out, "agents.jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception as e:  # a hook never gets in the way of the agent it observes
        print("retro hook: %s" % e, file=sys.stderr)
    return 0


def self_test():
    import tempfile
    fails = []

    def check(cond, what):
        if not cond:
            fails.append(what)

    def line(**kw):
        return json.dumps(kw) + "\n"

    with tempfile.TemporaryDirectory() as tmp:
        repo = os.path.join(tmp, "repo")
        os.makedirs(os.path.join(repo, ".ticket-auto"))
        with open(os.path.join(repo, ".ticket-auto", "run.log"), "w") as f:
            f.write("\n".join([
                "2026-11-01T10:00:00Z loop start v1 main --unattended",
                "2026-11-01T10:00:10Z loop gate start Start",
                "2026-11-01T10:01:00Z TE-1 claim",
                "2026-11-01T10:05:00Z TE-1 plan challenger PLAN STANDS → approve",
                "2026-11-01T10:20:00Z TE-1 tests 1 1 300",
                "2026-11-01T10:21:00Z TE-1 round 1 suite red → iterate",
                "2026-11-01T10:22:00Z TE-1 fix 1",
                "2026-11-01T10:40:00Z TE-1 tests 2 0 240",
                "2026-11-01T10:45:00Z TE-1 round 2 code-reviewer PASS → done",
                "2026-11-01T10:46:00Z TE-1 handoff review",
                "2026-11-01T10:47:00Z TE-2 claim",
                "2026-11-01T10:49:00Z TE-2 ask owner",
                "2026-11-01T10:50:00Z TE-2 owner Which API? → v2",
                "2026-11-01T10:55:00Z TE-2 gate plan Park",
                "2026-11-01T11:10:00Z TE-2 parked plan contested",
                "2026-11-01T11:11:00Z loop end",
                "2026-11-02T09:00:00Z loop start v2 main",
            ]) + "\n")
        slug = re.sub(r"[^A-Za-z0-9]", "-", repo)
        proj = os.path.join(tmp, "claude", slug)
        sid = "s1"
        os.makedirs(os.path.join(proj, sid, "subagents", "workflows", "wf_1"))
        os.makedirs(os.path.join(proj, sid, "workflows"))

        def call(mid, t, out=10, cr=1000, cw=0, tool=None, branch="main"):
            content = [{"type": "tool_use", "id": tool[0], "name": tool[1], "input": tool[2]}] if tool else []
            return line(type="assistant", timestamp=t, gitBranch=branch,
                        message={"id": mid, "usage": {"input_tokens": 1, "cache_read_input_tokens": cr,
                                                       "cache_creation_input_tokens": cw, "output_tokens": out},
                                 "content": content})

        def result(tid, t, error=False, branch="main"):
            return line(type="user", timestamp=t, gitBranch=branch,
                        message={"content": [{"type": "tool_result", "tool_use_id": tid, "is_error": error, "content": "boom"}]})
        with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
            f.write(line(type="user", timestamp="2026-11-01T09:59:00Z", gitBranch="main",
                         message={"content": "<command-name>/ticket:auto</command-name> v1"}))
            f.write(call("m1", "2026-11-01T10:00:05Z", tool=("q1", "AskUserQuestion", {})))
            f.write(result("q1", "2026-11-01T10:40:05Z"))                      # a 40-minute gate
            f.write(call("m1", "2026-11-01T10:00:06Z"))                          # same API call, not counted twice
            f.write(call("m2", "2026-11-01T10:41:00Z", out=20, cr=2000, tool=("b1", "Bash", {"command": "false"})))
            f.write(result("b1", "2026-11-01T10:41:01Z", error=True))
            f.write(call("m3", "2026-11-01T12:00:00Z", branch="ticket/TE-1-x"))  # attended, after the loop
            f.write(call("m4", "2026-11-03T12:00:00Z"))                           # outside the span
        ag = os.path.join(proj, sid, "subagents", "workflows", "wf_1", "agent-a1")
        with open(ag + ".jsonl", "w") as f:
            f.write(line(type="user", timestamp="2026-11-01T10:02:00Z",
                         message={"content": "Read .claude/references/auto/implementer.md and follow it.\nMODE: plan\nTICKET: TE-1"}))
            for i in range(3):
                f.write(call("a%d" % i, "2026-11-01T10:0%d:00Z" % (3 + i), cw=500,
                             tool=("t%d" % i, "Bash", {"command": "git status"})))
                f.write(result("t%d" % i, "2026-11-01T10:0%d:01Z" % (3 + i)))
        json.dump({"agentType": "general-purpose", "description": ""}, open(ag + ".meta.json", "w"))
        os.makedirs(os.path.join(proj, "s0", "subagents"))                       # a resumed session's copy, no meta
        with open(os.path.join(proj, "s0", "subagents", "agent-a1.jsonl"), "w") as f:
            f.write(open(ag + ".jsonl").read())
        json.dump({"runId": "wf_1", "workflowName": "ticket-auto", "status": "completed", "agentCount": 1,
                   "durationMs": 600000, "totalTokens": 1234, "startTime": "2026-11-01T10:01:30Z"},
                  open(os.path.join(proj, sid, "workflows", "wf_1.json"), "w"))
        codex_root = os.path.join(tmp, "codex", "2026", "11", "01")
        os.makedirs(codex_root)
        with open(os.path.join(codex_root, "rollout-x.jsonl"), "w") as f:
            f.write(line(type="session_meta", timestamp="2026-11-01T10:30:00Z", payload={"cwd": repo}))
            f.write(line(type="event_msg", timestamp="2026-11-01T10:30:01Z",
                         payload={"type": "user_message", "message": "Read .agents/references/auto/implementer.md and follow it.\nMODE: fix\nTICKET: TE-1"}))
            for i, (inp, cached, out) in enumerate([(1000, 0, 100), (2500, 1000, 150), (2500, 1000, 150)]):
                f.write(line(type="event_msg", timestamp="2026-11-01T10:31:0%dZ" % i,
                             payload={"type": "token_count", "info": {"total_token_usage": {
                                 "input_tokens": inp, "cached_input_tokens": cached, "output_tokens": out}}}))
        cfg = {"backend.type": "filesystem", "ticket_id.prefix": "TE", "git.branch_prefix": "ticket/"}
        closes = lambda ids: {"TE-1": {"closed": ts("2026-11-02T10:46:00Z"), "rejects": [ts("2026-11-01T18:00:00Z")]}}
        m, out = extract("v1", repo, [repo], os.path.join(tmp, "claude"), os.path.join(tmp, "codex"), cfg,
                         {"TE-1": {"title": "One"}, "TE-2": {"title": "Two"}}, closes)

        check(m["span"]["hours"] == 1.2, "span from the v1 window only")
        check(m["outcomes"] == {"handoff-review": 1, "parked": 1}, "outcomes %s" % m["outcomes"])
        t1 = m["tickets"]["TE-1"]
        check(len(t1["rounds"]) == 2 and t1["rounds"][1]["decision"] == "done", "TE-1 rounds")
        check(t1["suite_s"] == 540 and t1["red_runs"] == 1, "TE-1 suite seconds / red runs")
        check(t1["claim_to_handoff_s"] == 45 * 60, "TE-1 claim to hand-off")
        check(t1.get("review_wait_s") == 86400 and t1.get("rejected_after_handoff") == 1, "TE-1 review wait and reject")
        h = m["humans"]
        check(h["gates"] == {"start": 1, "plan": 1} and h["owner_questions"] == 1 and h["parked"] == 1, "loop humans %s" % h)
        check(h["asks"] == 1 and h["ask_wait_s"] == 2400, "AskUserQuestion count and wait %s" % h)
        check("a gate waited 40m" in out, "long gate in outliers")
        tot = m["tokens"]["tok_eq_totals"]
        orch = 1 + 0.1 * 1000 + 5 * 10 + 1 + 0.1 * 2000 + 5 * 20
        check(tot.get("orchestrator") == round(orch), "orchestrator tok_eq %s != %s" % (tot.get("orchestrator"), orch))
        check(tot.get("attended") == round(1 + 100 + 50), "attended tok_eq %s" % tot.get("attended"))
        check("overhead" not in tot, "out-of-span call ignored")
        types = m["tokens"]["agent_types"]
        check("implementer" in types and types["implementer"]["n"] == 2, "a Claude workflow and a Codex implementer %s" % types)
        imp = [a for a in m["agents"] if a["type"] == "implementer"][0]
        check(imp["ticket"] == "TE-1" and imp["workflow"] == "wf_1" and imp["repeated_commands"] == 1, "implementer record")
        cx = [a for a in m["agents"] if a["assistant"] == "codex"]
        check(len(cx) == 1 and cx[0]["calls"] == 2 and cx[0]["cr"] == 1000 and cx[0]["in"] == 1500 and cx[0]["out"] == 150,
              "codex deltas %s" % (cx[0] if cx else None))
        check(m["coverage"]["transcript_readers"] == ["claude", "codex"], "readers")
        check(m["tokens"]["workflow_runs"][0]["total_tokens"] == 1234, "workflow run record")
        check("TE-2: parked" in out and "Bash: false" not in json.dumps(m), "outliers / no transcript text in metrics")
        check(not any("_path" in a for a in m["agents"]), "no transcript paths in metrics")
    for f in fails:
        print("FAIL: " + f)
    print("retro-extract self-test: %s" % ("ok" if not fails else "%d failed" % len(fails)))
    return 1 if fails else 0


def main(argv):
    if argv[:1] == ["--hook"]:
        return hook()
    if argv[:1] == ["--self-test"]:
        return self_test()
    if not argv or argv[0].startswith("-"):
        print(__doc__.strip().split("\n\n")[0])
        return 64
    milestone, opts, i = argv[0], {}, 1
    while i < len(argv):
        a = argv[i]
        if a == "--no-tickets":
            opts["no_tickets"] = True
            i += 1
        elif a in ("--since", "--until", "--out", "--claude-root", "--codex-root") and i + 1 < len(argv):
            opts[a[2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            print("retro-extract: unknown argument %s" % a, file=sys.stderr)
            return 64
    main = main_checkout()
    cfg = load_config(main)
    if not cfg:
        print("retro-extract: no valid config (te config validate failed)", file=sys.stderr)
        return 1
    tickets = {} if opts.get("no_tickets") else milestone_tickets(main, milestone)
    home = os.path.expanduser("~")
    claude_root = opts.get("claude_root") or os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude"), "projects")
    codex_root = opts.get("codex_root") or os.path.join(os.environ.get("CODEX_HOME") or os.path.join(home, ".codex"), "sessions")
    metrics, out = extract(milestone, main, worktrees(main), claude_root, codex_root, cfg, tickets,
                           lambda ids: human_closes(main, cfg, ids), opts.get("since"), opts.get("until"))
    out_dir = opts.get("out") or os.path.join(main, "docs", "retros")
    os.makedirs(out_dir, exist_ok=True)
    mpath = os.path.join(out_dir, "%s.metrics.json" % milestone)
    with open(mpath, "w") as f:
        json.dump(metrics, f, indent=1, sort_keys=True)
        f.write("\n")
    odir = os.path.join(main, ".ticket-auto", "retro", milestone)
    os.makedirs(odir, exist_ok=True)
    with open(os.path.join(odir, "outliers.md"), "w") as f:
        f.write(out)
    c = metrics["coverage"]
    print("retro-extract: %s — %d session(s), %d agent(s) (%d from the hook only), readers: %s" % (
        milestone, c["sessions"], c["agents"], c["agents_from_hook_only"], ", ".join(c["transcript_readers"])))
    if c["handed_off_without_agent_transcripts"]:
        print("retro-extract: WARNING handed off with no agent transcript here: %s" %
              ", ".join(c["handed_off_without_agent_transcripts"]))
    if not c["agents"]:
        print("retro-extract: WARNING no agents found: the token numbers cover only the sessions")
    print("wrote %s and %s" % (os.path.relpath(mpath, main), os.path.relpath(os.path.join(odir, "outliers.md"), main)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
