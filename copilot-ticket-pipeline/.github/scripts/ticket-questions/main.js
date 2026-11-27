'use strict';
// Entry point for .github/workflows/ticket-questions.yml (actions/github-script).
// No AI involved: parses comment commands and keeps labels in line with ticket format v1.

const F = require('./format.js');

const OPEN_LABEL = process.env.OPEN_LABEL || 'open questions';
const FORMAT_ERROR_LABEL = process.env.FORMAT_ERROR_LABEL || 'ticket-format-error';
const MAX_BODY = 65536;

module.exports = async ({ github, context, core }) => {
  const { owner, repo } = context.repo;
  const payloadIssue = context.payload.issue;
  if (!payloadIssue || payloadIssue.pull_request) return;
  const issue_number = payloadIssue.number;

  // Always work on the live issue, never on the (possibly stale) event payload.
  const { data: issue } = await github.rest.issues.get({ owner, repo, issue_number });
  const labels = new Set((issue.labels || []).map((l) => (typeof l === 'string' ? l : l.name)));

  const ensureLabel = async (name, color, description) => {
    try {
      await github.rest.issues.getLabel({ owner, repo, name });
    } catch (e) {
      if (e.status !== 404) throw e;
      await github.rest.issues.createLabel({ owner, repo, name, color, description });
    }
  };
  const setLabel = async (name, present, color, description) => {
    if (present && !labels.has(name)) {
      await ensureLabel(name, color, description);
      await github.rest.issues.addLabels({ owner, repo, issue_number, labels: [name] });
      labels.add(name);
    } else if (!present && labels.has(name)) {
      try {
        await github.rest.issues.removeLabel({ owner, repo, issue_number, name });
      } catch (e) {
        if (e.status !== 404) throw e;
      }
      labels.delete(name);
    }
  };
  const setOpen = (present) => setLabel(OPEN_LABEL, present, 'd93f0b', 'Ticket has open questions — not ready for development');
  const setFormatError = (present) => setLabel(FORMAT_ERROR_LABEL, present, 'b60205', 'Ticket body breaks ticket format v1');
  const reply = (body) => github.rest.issues.createComment({ owner, repo, issue_number, body });
  const react = (comment_id, content) =>
    github.rest.reactions.createForIssueComment({ owner, repo, comment_id, content }).catch(() => {});

  const body = issue.body || '';
  const managed = F.isManaged(body);

  // ---- issue opened / edited / reopened / (un)labeled: label sync only ----
  if (context.eventName === 'issues') {
    if (!managed) return core.info('Not a ticket-format v1 issue — ignored.');
    const parsed = F.parse(body);
    // A question deleted in this edit is a format error too (F§1: append-only).
    const before = context.payload.changes && context.payload.changes.body && context.payload.changes.body.from;
    if (before !== undefined) {
      for (const id of F.vanishedIds(before, body)) {
        parsed.errors.push(`${id} was deleted in this edit — questions must never be deleted (restore it from the issue's edit history)`);
      }
    }
    if (parsed.errors.length) {
      const firstTime = !labels.has(FORMAT_ERROR_LABEL);
      await setFormatError(true);
      await setOpen(true); // fail closed
      if (firstTime) {
        await reply([
          'The ticket body no longer matches ticket format v1, so it is treated as having open questions.',
          '',
          ...parsed.errors.map((e) => `- ${e}`),
          '',
          'Restore the question markers (see `.github/ticket-system/ticket-format.md`), or run `ticket-refine` to repair it.',
        ].join('\n'));
      }
      return;
    }
    await setFormatError(false);
    const open = F.countOpen(parsed.blocks);
    await setOpen(open > 0);
    return core.info(`Label sync: ${open} open question(s).`);
  }

  // ---- issue_comment created: commands ----
  const comment = context.payload.comment;
  if (!comment || (comment.user && comment.user.type === 'Bot')) return;
  const commands = F.parseCommands(comment.body || '');
  if (commands.length === 0) return core.info('No commands in comment.');

  if (!managed) {
    await reply(`@${comment.user.login} \`/answer\`, \`/ask\` and \`/obsolete\` only work on tickets created with \`ticket-create\` (ticket format v1). Nothing was changed.`);
    return;
  }

  // Only people the repository knows: owners, org members and (outside) collaborators.
  // On public repos the permission API alone is not enough to exclude strangers.
  const association = comment.author_association || 'NONE';
  if (!['OWNER', 'MEMBER', 'COLLABORATOR'].includes(association)) {
    await react(comment.id, 'confused');
    await reply(`@${comment.user.login} only repository collaborators and organization members can use \`/answer\`, \`/ask\` and \`/obsolete\`. Ask a maintainer to add you as a collaborator (read access is enough). Nothing was changed.`);
    return;
  }

  let permission = 'none';
  let roleName = 'none';
  try {
    const { data } = await github.rest.repos.getCollaboratorPermissionLevel({ owner, repo, username: comment.user.login });
    permission = data.permission || 'none'; // admin | write | read | none
    roleName = data.role_name || permission; // admin | maintain | write | triage | read | custom
  } catch (e) {
    if (e.status !== 404) throw e;
  }

  const actor = { login: comment.user.login, permission, roleName };
  const meta = { date: new Date().toISOString().slice(0, 10), commentUrl: comment.html_url };
  const result = F.applyCommands(body, commands, actor, meta);

  if (!result.errors.length && result.body.length > MAX_BODY) {
    result.errors.push(`the ticket body would exceed GitHub's limit of ${MAX_BODY} characters.`);
  }
  if (result.errors.length) {
    await react(comment.id, 'confused');
    await reply([
      `@${actor.login} nothing was changed — please fix and post again:`,
      '',
      ...result.errors.map((e) => `- ${e}`),
    ].join('\n'));
    return;
  }

  await github.rest.issues.update({ owner, repo, issue_number, body: result.body });
  await setFormatError(false);
  await setOpen(result.openAfter > 0);
  await react(comment.id, '+1');
  core.info(`Applied: ${result.changes.join(', ')} — ${result.openAfter} open question(s) left.`);

  if (result.openBefore === 0 && result.openAfter > 0) {
    await reply([
      'This ticket has open questions again, so it is **not ready for development**.',
      '',
      'If it is in the **Ready** lane, move it back to **Backlog** (the next `ticket-refine` session does this automatically).',
    ].join('\n'));
  }
  if (result.openBefore > 0 && result.openAfter === 0) {
    await reply([
      'All open questions are resolved. 🎉',
      '',
      'Next step: run `ticket-refine` on this issue to fold the answers into the summary, scope and acceptance criteria, then move it to **Ready**.',
    ].join('\n'));
  }
};
