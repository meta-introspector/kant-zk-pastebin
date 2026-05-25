# apply.nix — Apply the idea cloud to scanned artifacts
#
# Takes:
#   lib       — nixpkgs lib for attribute/list processing
#   ideacloud — the idea cloud (from ./ideacloud.nix)
#   scan      — list of { path, content } scanned from the repo
#
# Returns:
#   reverseIndex — idea id → [matched artifact paths]
#   topo         — topologically sorted idea list
#   matched      — idea id → [{ path, content, idea }] full matches

{ lib, ideacloud, scan }:

let
  # Check if a file matches an idea's fingerprint
  matchFingerprint = idea: file:
    let
      fp = idea.fingerprint;
      # Check filetype pattern (glob-like suffix/prefix matching)
      okFiletype =
        if fp ? filetype then
          let
            ft = fp.filetype;
            path = file.path;
          in
          lib.hasSuffix ft path
        else true;
      # Check grep pattern in content using substring match
      okGrep =
        if fp ? grep then
          # Split on | for alternation patterns
          let
            patterns = lib.splitString "|" fp.grep;
            anyMatch = lib.any (pat: lib.hasInfix pat file.content) patterns;
          in anyMatch
        else true;
    in okFiletype && okGrep;

  # Build reverse index: idea id → list of matching file paths
  reverseIndex =
    lib.foldl'
      (acc: idea:
        let
          hits = lib.filter (file: matchFingerprint idea file) scan;
          hitPaths = map (f: f.path) hits;
        in
        acc // { ${idea.id} = hitPaths; }
      )
      { }
      ideacloud.ideas;

  # Attach idea metadata to matched results
  matched =
    lib.listToAttrs (map
      (idea:
        let
          hits = reverseIndex.${idea.id} or [];
          matchData = map (path:
            let file = lib.findFirst (f: f.path == path) null scan;
            in { inherit path; content = if file != null then file.content else ""; }
          ) hits;
        in
        { name = idea.id; value = matchData; }
      )
      ideacloud.ideas
    );

  # Topological sort
  topoResult = ideacloud.topoSort lib;
  topo = topoResult.result or [ ];

in {
  inherit reverseIndex matched topo;
  topoResult = topoResult;
  ideaCount = builtins.length ideacloud.ideas;
  scanCount = builtins.length scan;
}
