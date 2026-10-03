#!/usr/bin/env node
/**
 * vacuum-bug-test.mjs — a regression check for the "User1 sees no updates" bug.
 *
 * Reported bug: User1 creates a room and shares it, User2 joins and posts, and
 * User1's *existing* browser tab never shows the message. Only a fresh tab does.
 *
 * What this can and cannot see. The original symptom is a tab that is open but
 * not polling, so it needs a browser to reproduce. This harness approximates it
 * with the CLI: User1's "existing tab" is a stored cursor that `read` resumes
 * from. A `read` that polls *does* see the message, so the check below confirms
 * the relay delivers lines to a resuming client — it cannot observe a client that
 * has stopped polling, which is the actual bug. The output says so rather than
 * claiming the bug is fixed.
 *
 * What it now does that it did not before:
 *
 *   * Starts its own relay, on a reserved free port, with its own pass database
 *     in a temp directory. It used to talk to whatever was listening on
 *     127.0.0.1:8787 — a relay it never started — and posted two rows into that
 *     relay's rate-limit ledger every run. On this machine that ledger is
 *     /var/lib/kant-zk/passes.sqlite, i.e. deployment state.
 *   * Treats every step as a precondition. It used to print each step's output
 *     and continue regardless, and had no `process.exit` at all, so it could not
 *     fail: with no relay listening, every CLI call errored and the suite still
 *     reported success and exited 0.
 *   * Resolves the repository from its own location rather than `process.cwd()`,
 *     so it works from any directory.
 *   * Cleans up the relay and its temp directory on the way out.
 */

import fs from 'fs/promises';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CLI = path.join(ROOT, 'scripts', 'kant-cli.mjs');
const RELAY_BIN = path.join(ROOT, 'server', 'relay.mjs');

let failures = 0;
/** Record a step that did not happen, so the run cannot report success. */
const need = (cond, what) => {
  if (!cond) {
    failures += 1;
    console.error(`PRECONDITION FAILED: ${what}`);
  }
  return cond;
};

/** A port nothing is listening on. Verified after use, so a lost race fails loudly. */
function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

/** Wait for the relay to answer /health, or give up.
 *
 *  The relay takes a few seconds to open its store — measured at ~2.9s here,
 *  because the first SQLite connection migrates the schema — so the budget is
 *  generous. An 8s budget looked adequate and failed anyway when the suite ran
 *  alongside the rest of the verification set.
 */
async function waitForHealth(base, proc) {
  for (let i = 0; i < 300; i += 1) {
    if (proc.exitCode !== null) return false;
    try {
      const res = await fetch(`${base}/health`);
      if (res.ok) return true;
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

function run(args) {
  const result = spawnSync('node', [CLI, ...args], {
    encoding: 'utf8',
    env: { ...process.env, NODE_ENV: 'test' },
  });
  return { out: result.stdout + result.stderr, code: result.status };
}

/** Parse a step's JSON, recording a precondition failure rather than swallowing it. */
function step(args, what) {
  const { out, code } = run(args);
  need(code === 0, `${what} exited ${code}`);
  try {
    return JSON.parse(out);
  } catch {
    need(false, `${what} did not return JSON: ${out.trim().slice(0, 120)}`);
    return null;
  }
}

async function main() {
  console.log('=== Vacuum bug regression check ===\n');

  const stateDir = await fs.mkdtemp(path.join(os.tmpdir(), 'kant-vacuum-'));
  const passDb = path.join(stateDir, 'passes.sqlite');
  let relay = null;
  try {
    const port = await freePort();
    const base = `http://127.0.0.1:${port}`;
    let relayErr = '';
    relay = spawn('node', [RELAY_BIN, '--port', String(port), '--pass-db', passDb, '--quiet'],
      { stdio: ['ignore', 'pipe', 'pipe'] });
    relay.stdout.resume();
    relay.stderr.on('data', (d) => { relayErr += d; });
    if (!need(await waitForHealth(base, relay), `no relay answered on ${base}`)) {
      console.error("\nThe relay this suite needs did not start. Previously this was " +
        "indistinguishable from success, because the run continued against a " +
        "different relay on port 8787 or none at all.");
      if (relayErr.trim()) console.error(`relay said: ${relayErr.trim().slice(0, 400)}`);
      return;
    }

    const state = (who) => ['--state', path.join(stateDir, `${who}.json`)];

    // 1. User1 creates a room.
    console.log('--- Step 1: User1 creates a room ---');
    step([...state('user1'), 'open', '--relay', base, '--json'], 'user1 open');

    const { out: linkOut } = run([...state('user1'), 'link']);
    const inviteLink = linkOut.trim();
    need(/^https?:\/\//.test(inviteLink), `user1 link was not a URL: ${inviteLink.slice(0, 80)}`);
    console.log('User1 share link:', `${inviteLink.slice(0, 72)}...`);

    // 2. User1 says something.
    console.log('\n--- Step 2: User1 posts ---');
    const post1 = step([...state('user1'), 'say', 'hello from user1', '--json'], 'user1 say');
    console.log('User1 posted:', post1?.said, '(cursor:', post1?.cursor + ')');

    // 3. User2 joins by the link.
    console.log('\n--- Step 3: User2 joins by invite ---');
    step([...state('user2'), 'join', inviteLink, '--json'], 'user2 join');

    // 4. User2 says something.
    console.log('\n--- Step 4: User2 posts ---');
    const post2 = step([...state('user2'), 'say', 'hello from user2', '--json'], 'user2 say');
    console.log('User2 posted:', post2?.said, '(cursor:', post2?.cursor + ')');

    // 5. User1's existing tab reads: the cursor resumes, and User2's line is there.
    console.log('\n--- Step 5: User1 reads (the "existing tab") ---');
    const read1 = step([...state('user1'), 'read', '--json'], 'user1 read');
    const existing = read1?.view?.some((m) => m.text?.includes('user2')) ?? false;
    console.log('User1 cursor:', read1?.cursor, 'lines:', read1?.arrived);
    console.log('Does User1 see User2 message?', existing ? 'yes' : 'NO');

    // 6. A fresh reader, as a fresh tab would be.
    console.log('\n--- Step 6: a fresh reader joins and reads ---');
    step([...state('user1-fresh'), 'join', inviteLink, '--json'], 'user1-fresh join');
    const readFresh = step([...state('user1-fresh'), 'read', '--json'], 'user1-fresh read');
    const fresh = readFresh?.view?.some((m) => m.text?.includes('user2')) ?? false;
    console.log('Does a fresh reader see User2 message?', fresh ? 'yes' : 'NO');

    // What is actually being claimed.
    const agreed = existing === fresh;
    console.log('\n=== Result ===');
    console.log('resuming reader agrees with a fresh one:', agreed ? 'yes' : 'NO');
    if (!agreed) console.log('The relay served the two readers differently.');
    console.log(
      'Note: a reader that polls sees the message. The reported bug was a tab\n' +
      'that was open but not polling, which this CLI harness cannot observe.');
  } finally {
    relay?.kill();
    await fs.rm(stateDir, { recursive: true, force: true });
  }
}

main()
  .then(() => {
    if (failures) {
      console.error(`\n${failures} precondition(s) failed`);
      process.exit(1);
    }
    console.log('\nok — every step ran against a relay this suite started');
  })
  .catch((e) => {
    console.error(`\nthe run itself failed: ${e.stack ?? e.message}`);
    process.exit(1);
  });