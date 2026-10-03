# Kant e2e evidence — two browsers, one room

`node scripts/kant-e2e.mjs` opens two real Chromium windows on an Xvfb
screen, has the first open a room, has the second join by the invite
link, and has them exchange lines through the local relay
(`kant-relay.service`, :8787). Every run is recorded three ways:

| artifact | what it is |
|---|---|
| `screen-recording.mp4` | ffmpeg capture of the Xvfb screen (`:99`, also visible live over VNC on :5900) |
| `network-flows.mitm` | every HTTP exchange, captured by mitmdump :8280 (the browsers are proxied through it, loopback included) |
| `timeline.json` + `0*.png` | per-step screenshots and the machine-readable timeline of the run |

Checks asserted at the end: relay healthy, A opened a room, B joined by
link, A sees B's line, B sees A's line.

## Reproduce

```sh
# display + VNC (optional, for watching live)
Xvfb :99 -screen 0 1600x1000x24 &
x11vnc -display :99 -forever -shared -nopw &

# network capture
mitmdump --listen-port 8280 -w /tmp/kant-e2e-flows.mitm \
  --set flow_detail=0 --set console_eventlog_verbosity=warn &

# screen capture
ffmpeg -y -f x11grab -video_size 1600x1000 -i :99 -framerate 10 \
  -pix_fmt yuv420p -t 120 /tmp/kant-e2e-screen.mp4 &

# the run itself (playwright comes from ~/projects/arist/gui2lean4)
node scripts/kant-e2e.mjs          # -> e2e-out/, exit 1 on any failed check

# inspect the network capture afterwards
mitmdump -nr e2e-out/network-flows.mitm
```

Notes:

- The served `kant.config` names the deployed relay; the test routes
  `**/kant.config` to a local config so the run is hermetic.
- Chromium bypasses the proxy for localhost by default — the launch
  args pass `--proxy-bypass-list=<-loopback>` so loopback traffic shows
  up in the capture.
- `waitUntil: "load"`, not `"networkidle"`: the page holds a 25 s
  relay long-poll open the whole time, so the network is never idle.
