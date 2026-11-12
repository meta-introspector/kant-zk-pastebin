// INT44-01 CI test: cardSvg rejects javascript:/data:/vbscript:/file: schemes
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const SRC = resolve(here, "../web/kant-site.mjs");
const mod = await import(SRC);
const { cardSvg } = mod;

let passed = 0, failed = 0;
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
  if (ok) passed++; else { failed++; console.log(`        actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`); }
};

// Use a minimal but correct QR shape: { size, modules } where modules is 2D.
// cardSvg iterates r, c over size and reads modules[r][c].
const qr = {
  size: 5,
  modules: Array.from({ length: 5 }, () => Array(5).fill(0)),
};
const mkCard = (url) => ({ url, caption: "t", picture: "", alt: "t", room: "r", sender: "s", seq: 0 });

check("javascript: rejected", /<a href="javascript:/.test(cardSvg(mkCard("javascript:alert(1)"), qr)), false);
check("data: rejected", /<a href="data:/.test(cardSvg(mkCard("data:text/html,<script>x</script>"), qr)), false);
check("vbscript: rejected", /<a href="vbscript:/.test(cardSvg(mkCard("vbscript:x"), qr)), false);
check("file: rejected", /<a href="file:/.test(cardSvg(mkCard("file:///etc/passwd"), qr)), false);
check("https kept", /<a href="https:\/\/example\.com\/x">/.test(cardSvg(mkCard("https://example.com/x"), qr)), true);
check("http kept", /<a href="http:\/\/example\.com\/x">/.test(cardSvg(mkCard("http://example.com/x"), qr)), true);

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
