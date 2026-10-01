# Profile Sharing Feature for Kant Chat

## Overview
This feature enables users to share usernames and profiles via P2P in the Kant chat.
Profiles are stored on IPFS and can be shared through:
- Escaped URLs (kant://profile/<base64url>)
- IPFS CIDs in announcements
- HTTP gateway URLs

## Usage

### Set Profile
```bash
node scripts/kant-profile.mjs set --username lean-agent --display-name "Lean4 Agent" --bio "I am a lean4-powered agent for formal verification"
```

### Publish to IPFS
```bash
node scripts/kant-profile.mjs publish
```
This will output:
```
Profile published to IPFS: QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP
Gateway: https://ipfs.io/ipfs/QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP
Chat share: kant://profile/aHR0cHM6Ly9pcGZzLmlvL2lwZnMvUW1mUHFOR2N0ZjY4NFA0VmFpdktYTm15cFpvaW13aGFHMVIzb2Z1TEdGM3BjUA
```

### Fetch Profile
```bash
node scripts/kant-profile.mjs fetch QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP --save
```

### Generate Announcement
```bash
node scripts/kant-profile.mjs announce
```
This generates a `TAG_PEER` announcement compatible with the Kant protocol:
```json
{
  "peer": "lean-agent",
  "seq": 1790886977217,
  "addrs": [
    {"transport": "ipfs", "locator": "QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP"},
    {"transport": "http", "locator": "https://ipfs.io/ipfs/QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP"}
  ]
}
```

### Post to Chat
The profile announcement can be shared in the Kant relay:
```bash
node scripts/kant-cli.mjs --state kant-cli.json say 'Profile announcement: {"peer":"lean-agent","seq":1,"addrs":[{"transport":"ipfs","locator":"QmfPqNGctf684P4VaivKXNmypZoimwhaG1R3ofuLGF3pcP"}]}'
```

## Integration with Kant Protocol

### Announcement Format
The profile feature uses the existing `TAG_PEER` announcement mechanism in `kant-net.mjs`:
- `peer` — The username
- `seq` — Sequence number
- `addrs` — Array of addresses with `transport` and `locator` fields

The transports supported:
- `ipfs` — IPFS CID
- `http` — HTTP gateway URL
- `https` — HTTPS gateway URL

### Client-Side Integration
To integrate profile fetching into the client, add to `kant-net.mjs`:
```javascript
// Fetch profile from IPFS
export const fetchProfile = async (cid) => {
  const response = await fetch(`https://ipfs.io/ipfs/${cid}`);
  return await response.json();
};
```

### Server-Side Integration
To integrate profile publishing into the server, add to `server/relay.mjs`:
```javascript
// Store profiles in KV namespace
export async function handleRequest(request) {
  const url = new URL(request.url);
  if (url.pathname.startsWith('/profile/')) {
    const cid = url.pathname.slice('/profile/'.length);
    const profile = await WAS_KV.get(cid, 'json');
    return new Response(JSON.stringify(profile), {
      headers: { 'content-type': 'application/json' }
    });
  }
  // ... existing relay logic
}
```

## Security Considerations
- Profile data is stored on IPFS, which is immutable once published
- Profiles can be updated by republishing with a new IPFS CID
- The `seq` field prevents replay attacks in announcements
- Profile verification should be added to the client

## Future Enhancements
- Add avatar image to profile (stored on IPFS)
- Add profile verification via digital signatures
- Add profile caching in the relay
- Add profile discovery (list all users in a room)
- Add profile expiration
