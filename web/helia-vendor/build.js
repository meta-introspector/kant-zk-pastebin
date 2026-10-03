// Vendor bundle entry for Helia — built via flake.nix heliaVendor derivation.
// Output: web/vendor/helia.mjs (served by relay.mjs with text/javascript MIME).
// Only exports what kant-helia.mjs actually uses: createHelia and CID.
import { createHelia } from "helia";
import { CID } from "multiformats/cid";

export { createHelia };
export { CID };