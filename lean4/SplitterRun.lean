import Splitter

open KantSplitter

def main (args : List String) : IO UInt32 := do
  let path := args.getD 0 "/tmp/target-paste.txt"
  let text ← IO.FS.readFile path
  let chunks := splitText 4 Unit.word text
  IO.println s!"chunks={chunks.length}"
  for (i, chunk) in chunks.take 5 do
    IO.println s!"--- chunk {i} len={chunk.length} ---"
    IO.println chunk.take 200
  return 0
