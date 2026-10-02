# browser.nix — the browser the GUI2Lean4 captures run against.
#
#   nix build .#chromium
#   KANT_CHROMIUM=$(nix build .#chromium --print-out-paths)/bin/chromium \
#     node scripts/fileshare-capture.mjs --headed
#
# Playwright's bundled download is only chrome-headless-shell, which cannot
# open a window, so `--headed` needs a full browser from somewhere else.
# nixpkgs' chromium is the obvious answer: it is pinned by store hash, it
# needs no snap refresh and no network download at run time, and it works in
# both modes. `scripts/fileshare-capture.mjs` finds it by globbing the store
# for `*-chromium-*`, so this flake is a convenience and a record of intent
# rather than something the script depends on.
#
# Deliberately NOT here: a pinned `chrome-headless-shell`. The shell is
# smaller, but it is the reason headed runs were failing, and a browser that
# cannot open a window is the wrong thing to pin for a test that is supposed
# to prove a page renders.
{
  description = "Browser for the Kant GUI2Lean4 captures";

  # A real remote, not a local mirror path: this flake is evaluated by CI too.
  # Pinned by rev to the same nixpkgs the top-level flake uses, so the two
  # cannot drift. A real remote, not a local mirror path: CI evaluates this too.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: {
        # A full Chromium: both `--headless` and a real window on $DISPLAY.
        chromium = pkgs.chromium;

        # The headless shell alone, for when only headless is wanted and the
        # size matters. Not sufficient for `--headed`.
        chrome-headless-shell = pkgs.chromium.headless-shell or null;

        # The capture script plus the browser it should use, so the whole
        # thing can be run without asking where chromium came from:
        #   nix run .#fileshare-capture -- --headed
        fileshare-capture = pkgs.writeShellApplication {
          name = "fileshare-capture";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''
            exec ${pkgs.nodejs}/bin/node ${self}/scripts/fileshare-capture.mjs \
              --base "''${KANT_BASE_URL:-https://solana.solfunmeme.com/p2p-relay}" \
              "$@"
          '';
        };
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nodejs
            pkgs.chromium
            pkgs.ffmpeg
            pkgs.sqlite
          ];
          # Playwright is only used as a driver, never as the browser: its
          # bundled download is the headless shell and nothing else here.
          shellHook = ''
            echo "chromium: $(command -v chromium || echo none)"
            echo "display:  ''${DISPLAY:-(none)}"
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          '';
        };
      });

      apps.x86_64-linux.fileshare-capture = {
        type = "app";
        program = "${self.packages.x86_64-linux.fileshare-capture}/bin/fileshare-capture";
      };
    };
}