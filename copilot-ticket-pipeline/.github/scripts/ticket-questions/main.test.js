'use strict';
// Glue test for main.js with a mocked GitHub API.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const run = require('./main.js');

const TICKET = fs.readFileSync(path.join(__dirname, 'format.test.js'), 'utf8').match(/const TICKET = `([\s\S]*?)`;/)[1];

function mock({ body = TICKET, labels = [], permission = 'read', permStatus = 200, existingLabels = ['open questions'] } = {}) {
  const calls = [];
  const state = { body, labels: [...labels], comments: [], reactions: [], createdLabels: [] };
  const err = (status) => Object.assign(new Error(String(status)), { status });
  const github = {
    rest: {
      issues: {
        get: async () => ({ data: { body: state.body, labels: state.labels.map((name) => ({ name })) } }),
        update: async (a) => { calls.push('update'); state.body = a.body; },
        getLabel: async (a) => { if (!existingLabels.includes(a.name) && !state.createdLabels.includes(a.name)) throw err(404); },
        createLabel: async (a) => { state.createdLabels.push(a.name); },
        addLabels: async (a) => { state.labels.push(...a.labels); },
        removeLabel: async (a) => {
          if (!state.labels.includes(a.name)) throw err(404);
          state.labels = state.labels.filter((l) => l !== a.name);
        },
        createComment: async (a) => { state.comments.push(a.body); },
      },
      repos: {
        getCollaboratorPermissionLevel: async () => {
          if (permStatus !== 200) throw err(permStatus);
          return { data: { permission, role_name: permission } };
        },
      },
      reactions: { createForIssueComment: async (a) => { state.reactions.push(a.content); } },
    },
  };
  const core = { info: () => {} };
  return { github, core, state, calls };
}

const issuesEvent = { eventName: 'issues', repo: { owner: 'o', repo: 'r' }, payload: { issue: { number: 42 } } };
const commentEvent = (body, user = { login: 'carol', type: 'User' }, author_association = 'COLLABORATOR') => ({
  eventName: 'issue_comment',
  repo: { owner: 'o', repo: 'r' },
  payload: { issue: { number: 42 }, comment: { id: 7, body, user, author_association, html_url: 'https://github.com/o/r/issues/42#issuecomment-7' } },
});

test('issues event: adds open-questions label when questions are open', async () => {
  const m = mock();
  await run({ github: m.github, context: issuesEvent, core: m.core });
  assert.deepEqual(m.state.labels, ['open questions']);
  assert.equal(m.calls.length, 0); // never edits the body on sync
});

test('issues event: removes label when nothing is open', async () => {
  const F = require('./format.js');
  const actor = { login: 'carol', permission: 'read', roleName: 'read' };
  const { body } = F.applyCommands(TICKET, F.parseCommands('/answer Q2 50k\n/answer Q3 no'), actor, { date: '2026-10-12', commentUrl: 'u' });
  const m = mock({ body, labels: ['open questions'] });
  await run({ github: m.github, context: issuesEvent, core: m.core });
  assert.deepEqual(m.state.labels, []);
});

test('issues event: broken format fails closed, comments once', async () => {
  const body = TICKET.replace('<!-- /q:Q3 -->', '');
  const m = mock({ body });
  await run({ github: m.github, context: issuesEvent, core: m.core });
  assert.ok(m.state.labels.includes('ticket-format-error'));
  assert.ok(m.state.labels.includes('open questions'));
  assert.equal(m.state.comments.length, 1);
  assert.ok(m.state.createdLabels.includes('ticket-format-error')); // label auto-created
  await run({ github: m.github, context: issuesEvent, core: m.core });
  assert.equal(m.state.comments.length, 1); // no spam on further edits
});

test('issues event: unmanaged issue is ignored', async () => {
  const m = mock({ body: 'plain issue' });
  await run({ github: m.github, context: issuesEvent, core: m.core });
  assert.deepEqual(m.state.labels, []);
  assert.equal(m.state.comments.length, 0);
});

test('comment: answer applied, 👍, label kept while Q3 open', async () => {
  const m = mock({ labels: ['open questions'] });
  await run({ github: m.github, context: commentEvent('/answer Q2 50k rows'), core: m.core });
  assert.match(m.state.body, /<!-- q:Q2 status:answered -->/);
  assert.deepEqual(m.state.reactions, ['+1']);
  assert.deepEqual(m.state.labels, ['open questions']);
  assert.equal(m.state.comments.length, 0);
});

test('comment: last answer removes label and posts next-step comment', async () => {
  const m = mock({ labels: ['open questions'] });
  await run({ github: m.github, context: commentEvent('/answer Q2 50k\n/answer Q3 no'), core: m.core });
  assert.deepEqual(m.state.labels, []);
  assert.match(m.state.comments[0], /All open questions are resolved/);
});

test('comment: errors → nothing changed, 😕 and explanation', async () => {
  const m = mock({ labels: ['open questions'] });
  await run({ github: m.github, context: commentEvent('/answer Q1 again'), core: m.core });
  assert.equal(m.state.body, TICKET);
  assert.deepEqual(m.state.reactions, ['confused']);
  assert.match(m.state.comments[0], /nothing was changed[\s\S]*Q1 is already answered/);
});

test('comment: outsider without access (404) is refused', async () => {
  const m = mock({ permStatus: 404 });
  await run({ github: m.github, context: commentEvent('/answer Q2 50k'), core: m.core });
  assert.equal(m.state.body, TICKET);
  assert.match(m.state.comments[0], /needs at least read access/);
});

test('comment: strangers on public repos are refused by author_association', async () => {
  const m = mock({ permission: 'read' }); // permission API alone would say read
  await run({ github: m.github, context: commentEvent('/answer Q2 50k', undefined, 'NONE'), core: m.core });
  assert.equal(m.state.body, TICKET);
  assert.match(m.state.comments[0], /only repository collaborators and organization members/);
});

test('issues edited: deleting a question fails closed', async () => {
  const after = TICKET.replace(/<!-- q:Q3 status:open -->[\s\S]*?<!-- \/q:Q3 -->\n/, '');
  const m = mock({ body: after, labels: ['open questions'] });
  const ctx = { ...issuesEvent, payload: { issue: { number: 42 }, changes: { body: { from: TICKET } } } };
  await run({ github: m.github, context: ctx, core: m.core });
  assert.ok(m.state.labels.includes('ticket-format-error'));
  assert.ok(m.state.labels.includes('open questions'));
  assert.match(m.state.comments[0], /Q3 was deleted in this edit/);
});

test('issues unlabeled: a manually removed label comes back', async () => {
  const m = mock({ labels: [] }); // someone removed it
  await run({ github: m.github, context: { ...issuesEvent, payload: { issue: { number: 42 }, action: 'unlabeled' } }, core: m.core });
  assert.deepEqual(m.state.labels, ['open questions']);
});

test('comment: /ask on a ticket without open questions warns about the Ready lane', async () => {
  const body = TICKET.replace(/<!-- q:Q2 status:open -->[\s\S]*?<!-- \/q:Q3 -->/, '_None._');
  const m = mock({ body });
  await run({ github: m.github, context: commentEvent('/ask New question?'), core: m.core });
  assert.deepEqual(m.state.labels, ['open questions']);
  assert.match(m.state.comments[0], /move it back to \*\*Backlog\*\*/);
});

test('comment: bots, PRs, plain comments and unmanaged issues', async () => {
  const bot = mock();
  await run({ github: bot.github, context: commentEvent('/answer Q2 x', { login: 'x[bot]', type: 'Bot' }), core: bot.core });
  assert.equal(bot.state.body, TICKET);

  const pr = mock();
  const prEvent = commentEvent('/answer Q2 x');
  prEvent.payload.issue.pull_request = {};
  await run({ github: pr.github, context: prEvent, core: pr.core });
  assert.equal(pr.state.body, TICKET);

  const plain = mock();
  await run({ github: plain.github, context: commentEvent('Looks good to me'), core: plain.core });
  assert.equal(plain.state.comments.length, 0);

  const unmanaged = mock({ body: 'plain issue' });
  await run({ github: unmanaged.github, context: commentEvent('/answer Q2 x'), core: unmanaged.core });
  assert.match(unmanaged.state.comments[0], /only work on tickets created with `ticket-create`/);
});
