#!/usr/bin/env node
/**
 * kant-profile — User profile management for kant-zk-pastebin
 * 
 * Features:
 * - Set username and profile (bio, avatar, etc.)
 * - Publish profile to IPFS
 * - Fetch profiles via IPFS
 * - Include profile CID in announcements
 * - Escape URLs for sharing in chat
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";

// Profile structure
class KantProfile {
  constructor(data = {}) {
    this.username = data.username || "";
    this.displayName = data.displayName || "";
    this.bio = data.bio || "";
    this.avatar = data.avatar || ""; // Can be IPFS CID or data URL
    this.publicKey = data.publicKey || ""; // For verification
    this.created = data.created || new Date().toISOString();
    this.updated = data.updated || new Date().toISOString();
    this.ipfsCid = data.ipfsCid || "";
    this.addresses = data.addresses || []; // P2P addresses
  }

  toJSON() {
    return {
      username: this.username,
      displayName: this.displayName,
      bio: this.bio,
      avatar: this.avatar,
      publicKey: this.publicKey,
      created: this.created,
      updated: new Date().toISOString(),
      ipfsCid: this.ipfsCid,
      addresses: this.addresses
    };
  }

  static fromJSON(json) {
    return new KantProfile(json);
  }
}

// IPFS integration
async function addToIPFS(content) {
  // Try IPFS CLI first
  try {
    const result = spawnSync('ipfs', ['add', '-Q', '--pin=false'], {
      input: JSON.stringify(content, null, 2),
      encoding: 'utf8',
      maxBuffer: 1024 * 1024
    });
    if (result.status === 0 && result.stdout.trim()) {
      return result.stdout.trim();
    }
  } catch (e) {}

  // Try IPFS HTTP API
  try {
    const response = await fetch('http://127.0.0.1:5001/api/v0/add?pin=false', {
      method: 'POST',
      body: JSON.stringify(content, null, 2),
      headers: { 'Content-Type': 'application/json' }
    });
    if (response.ok) {
      const data = await response.json();
      return data.Hash;
    }
  } catch (e) {}

  // Try kubo gateway
  try {
    const response = await fetch('https://ipfs.io/api/v0/add?pin=false', {
      method: 'POST',
      body: JSON.stringify(content, null, 2),
      headers: { 'Content-Type': 'application/json' }
    });
    if (response.ok) {
      const data = await response.json();
      return data.Hash;
    }
  } catch (e) {}

  throw new Error('No IPFS endpoint available. Install IPFS or run local node.');
}

async function getFromIPFS(cid) {
  // Try IPFS gateway
  try {
    const response = await fetch(`https://ipfs.io/ipfs/${cid}`);
    if (response.ok) {
      return await response.json();
    }
  } catch (e) {}

  // Try local gateway
  try {
    const response = await fetch(`http://127.0.0.1:8080/ipfs/${cid}`);
    if (response.ok) {
      return await response.json();
    }
  } catch (e) {}

  throw new Error(`Failed to fetch from IPFS: ${cid}`);
}

// Escape URL for chat sharing
function escapeUrlForChat(url) {
  // Base64 encode the URL for safe sharing in chat
  const encoded = Buffer.from(url).toString('base64url');
  return `kant://profile/${encoded}`;
}

function unescapeUrlFromChat(escaped) {
  if (escaped.startsWith('kant://profile/')) {
    const encoded = escaped.slice('kant://profile/'.length);
    return Buffer.from(encoded, 'base64url').toString();
  }
  return escaped;
}

// CLI state management
const PROFILE_FILE = 'kant-profile.json';

function loadProfile() {
  if (existsSync(PROFILE_FILE)) {
    return KantProfile.fromJSON(JSON.parse(readFileSync(PROFILE_FILE, 'utf8')));
  }
  return new KantProfile();
}

function saveProfile(profile) {
  writeFileSync(PROFILE_FILE, JSON.stringify(profile.toJSON(), null, 2) + '\n');
}

// Commands
async function cmdSetProfile(args) {
  const profile = loadProfile();
  
  if (args.username) profile.username = args.username;
  if (args.displayName) profile.displayName = args.displayName;
  if (args.bio) profile.bio = args.bio;
  if (args.avatar) profile.avatar = args.avatar;
  
  profile.updated = new Date().toISOString();
  saveProfile(profile);
  
  console.log(`Profile updated for: ${profile.username || profile.displayName || 'anonymous'}`);
  console.log(JSON.stringify(profile.toJSON(), null, 2));
}

async function cmdPublishProfile() {
  const profile = loadProfile();
  
  if (!profile.username && !profile.displayName) {
    console.error('Error: Set a username or displayName first');
    process.exit(1);
  }

  console.log('Publishing profile to IPFS...');
  const cid = await addToIPFS(profile.toJSON());
  profile.ipfsCid = cid;
  profile.updated = new Date().toISOString();
  saveProfile(profile);
  
  console.log(`Profile published to IPFS: ${cid}`);
  console.log(`Gateway: https://ipfs.io/ipfs/${cid}`);
  console.log(`Chat share: ${escapeUrlForChat(`https://ipfs.io/ipfs/${cid}`)}`);
}

async function cmdFetchProfile(args) {
  let cid = args.cid;
  
  // Try to unescape if it's a chat-escaped URL
  if (cid.startsWith('kant://profile/')) {
    cid = unescapeUrlFromChat(cid);
  }
  
  // If it's a gateway URL, extract CID
  if (cid.startsWith('http')) {
    const match = cid.match(/\/ipfs\/([a-zA-Z0-9]+)/);
    if (match) cid = match[1];
  }
  
  console.log(`Fetching profile from IPFS: ${cid}`);
  const profileData = await getFromIPFS(cid);
  const profile = KantProfile.fromJSON(profileData);
  
  console.log('Profile:');
  console.log(JSON.stringify(profile.toJSON(), null, 2));
  
  if (args.save) {
    saveProfile(profile);
    console.log('Profile saved locally');
  }
}

async function cmdShowProfile() {
  const profile = loadProfile();
  console.log('Current Profile:');
  console.log(JSON.stringify(profile.toJSON(), null, 2));
  
  if (profile.ipfsCid) {
    console.log(`\nIPFS: https://ipfs.io/ipfs/${profile.ipfsCid}`);
    console.log(`Chat share: ${escapeUrlForChat(`https://ipfs.io/ipfs/${profile.ipfsCid}`)}`);
  }
}

async function cmdGenerateAnnounce() {
  const profile = loadProfile();
  
  if (!profile.username && !profile.displayName) {
    console.error('Error: Set a username or displayName first');
    process.exit(1);
  }
  
  if (!profile.ipfsCid) {
    console.error('Error: Publish profile to IPFS first');
    process.exit(1);
  }
  
  // Create announcement with profile CID
  const announceData = {
    peer: profile.username || profile.displayName,
    seq: Date.now(),
    addrs: [
      { transport: 'ipfs', locator: profile.ipfsCid },
      { transport: 'http', locator: `https://ipfs.io/ipfs/${profile.ipfsCid}` }
    ]
  };
  
  console.log('Announcement with profile:');
  console.log(JSON.stringify(announceData, null, 2));
  
  // Generate the text for sharing
  const shareText = JSON.stringify(announceData);
  console.log(`\nShare in chat: ${shareText}`);
}

function showHelp() {
  console.log(`
kant-profile — User profile management for kant-zk-pastebin

USAGE:
  kant-profile <command> [options]

COMMANDS:
  set [--username <name>] [--display-name <name>] [--bio <text>] [--avatar <url>]
      Set profile fields
  
  publish
      Publish profile to IPFS
  
  fetch <cid-or-url> [--save]
      Fetch profile from IPFS by CID or URL
  
  show
      Show current profile
  
  announce
      Generate announcement with profile CID for sharing

EXAMPLES:
  kant-profile set --username alice --bio "Lean4 researcher"
  kant-profile publish
  kant-profile fetch QmX5o5qeBUCoexgcTjXiRZt6y3nyJSaP7eK4QGstG8KXs4 --save
  kant-profile announce
  
  # In kant-cli, share profile:
  kant-cli --state a.json say "My profile: kant://profile/aHR0cHM6Ly9pcGZzLmlvL2lwZnMv..."
  kant-cli --state b.json accept kant://profile/aHR0cHM6Ly9pcGZzLmlvL2lwZnMv...
`);
}

// Main
async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  
  const parsed = {};
  for (let i = 1; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      parsed[key] = args[i + 1] && !args[i + 1].startsWith('--') ? args[++i] : true;
    }
  }
  
  switch (cmd) {
    case 'set':
      await cmdSetProfile(parsed);
      break;
    case 'publish':
      await cmdPublishProfile();
      break;
    case 'fetch':
      if (!parsed.cid && args[1] && !args[1].startsWith('--')) {
        parsed.cid = args[1];
      }
      if (!parsed.cid) {
        console.error('Error: CID or URL required');
        process.exit(1);
      }
      await cmdFetchProfile({ cid: parsed.cid, save: parsed.save });
      break;
    case 'show':
      await cmdShowProfile();
      break;
    case 'announce':
      await cmdGenerateAnnounce();
      break;
    case 'help':
    default:
      showHelp();
      break;
  }
}

main().catch(e => {
  console.error(e.message);
  process.exit(1);
});
