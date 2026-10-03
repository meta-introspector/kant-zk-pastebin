#!/usr/bin/env node
/**
 * vacuum-bug-test.mjs — Reproduces the "User1 sees no updates" bug
 *
 * Bug: When User1 creates a room, shares it, User2 joins and posts messages,
 * User1's existing browser tab doesn't see updates. Only a fresh browser/incognito
 * shows the new messages.
 */

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = process.cwd();
const CLI = path.join(ROOT, 'scripts/kant-cli.mjs');

const STATE_DIR = '/tmp/kant-bug-repro';
const RELAY = 'http://127.0.0.1:8787';

function run(args) {
  const result = spawnSync('node', [CLI, ...args], {
    encoding: 'utf8',
    env: { ...process.env, NODE_ENV: 'test' }
  });
  return result.stdout + result.stderr;
}

async function main() {
  console.log('=== Vacuum Bug Reproduction ===\n');
  console.log('Bug: User1 creates room, shares it, User2 joins and posts,');
  console.log('     User1 does not see updates in existing browser tab.\n');

  // Clean state
  await fs.rm(STATE_DIR, { recursive: true, force: true });
  await fs.mkdir(STATE_DIR, { recursive: true });

  // Step 1: User1 creates a room
  console.log('--- Step 1: User1 creates room ---');
  let output = await run(['--state', `${STATE_DIR}/user1.json`, 'open', '--relay', RELAY, '--json']);
  console.log(output.trim());
  console.log('');

  // Get the invite link
  output = await run(['--state', `${STATE_DIR}/user1.json`, 'link']);
  const inviteLink = output.trim();
  console.log('User1 share link:', inviteLink?.substring(0, 80) + '...');
  console.log('');

  // Step 2: User1 posts initial message
  console.log('--- Step 2: User1 posts initial message ---');
  output = await run(['--state', `${STATE_DIR}/user1.json`, 'say', 'hello from user1', '--json']);
  try {
    const post1 = JSON.parse(output);
    console.log('User1 posted:', post1.said, '(cursor:', post1.cursor + ')');
  } catch {
    console.log('User1 post output:', output.trim());
  }
  console.log('');

  // Step 3: User2 joins the room via invite link
  console.log('--- Step 3: User2 joins room via invite ---');
  output = await run(['--state', `${STATE_DIR}/user2.json`, 'join', inviteLink, '--json']);
  console.log(output.trim());
  console.log('');

  // Step 4: User2 posts a message
  console.log('--- Step 4: User2 posts "hello from user2" ---');
  output = await run(['--state', `${STATE_DIR}/user2.json`, 'say', 'hello from user2', '--json']);
  try {
    const post2 = JSON.parse(output);
    console.log('User2 posted:', post2.said, '(cursor:', post2.cursor + ')');
  } catch {
    console.log('User2 post output:', output.trim());
  }
  console.log('');

  // Step 5: User1 reads room (simulating "existing browser tab")
  console.log('--- Step 5: User1 reads room (existing browser tab) ---');
  output = await run(['--state', `${STATE_DIR}/user1.json`, 'read', '--json']);
  let read1;
  try {
    read1 = JSON.parse(output);
    console.log('User1 cursor:', read1.cursor, 'lines:', read1.arrived);
    console.log('User1 view (last 3 messages):');
    const view = read1.view?.slice(-3) || [];
    view.forEach(m => console.log(`  ${m.sender}: ${m.text}`));
  } catch {
    console.log('User1 read output:', output.trim());
  }
  console.log('');

  // Check if User2's message appears
  const hasUser2Message = read1?.view?.some(m => m.text.includes('user2'));
  console.log('Does User1 see User2 message?', hasUser2Message ? '✅ YES' : '❌ NO (BUG!)');
  console.log('');

  // Step 6: Simulate "new browser/incognito" - fresh state
  console.log('--- Step 6: User1 joins fresh (new browser/incognito) ---');
  output = await run(['--state', `${STATE_DIR}/user1-fresh.json`, 'join', inviteLink, '--json']);
  console.log(output.trim());
  console.log('');

  // Fresh read
  console.log('--- Step 6b: Fresh User1 reads room ---');
  output = await run(['--state', `${STATE_DIR}/user1-fresh.json`, 'read', '--json']);
  let readFresh;
  try {
    readFresh = JSON.parse(output);
    console.log('Fresh cursor:', readFresh.cursor, 'lines:', readFresh.arrived);
    console.log('Fresh view (last 3 messages):');
    const freshView = readFresh.view?.slice(-3) || [];
    freshView.forEach(m => console.log(`  ${m.sender}: ${m.text}`));
  } catch {
    console.log('Fresh read output:', output.trim());
  }
  console.log('');

  const hasUser2Fresh = readFresh?.view?.some(m => m.text.includes('user2'));
  console.log('Does fresh User1 see User2 message?', hasUser2Fresh ? '✅ YES' : '❌ NO');
  console.log('');

  // Summary
  console.log('=== Bug Summary ===');
  console.log('User1 existing tab sees User2 message:', hasUser2Message ? '✅' : '❌');
  console.log('User1 fresh browser sees User2 message:', hasUser2Fresh ? '✅' : '❌');
  console.log('');
  if (!hasUser2Message) {
    console.log('BUG CONFIRMED: Existing browser tab does not receive updates.');
    console.log('FIX: Enable automatic polling when page gains focus (window.onfocus)');
    console.log('     or use WebSocket connections for real-time updates.');
  } else {
    console.log('No bug detected - or the bug was already fixed.');
  }

  // Cleanup
  await fs.rm(STATE_DIR, { recursive: true, force: true });
}

main().catch(console.error);