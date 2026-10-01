namespace KantSplitter

inductive Unit where
  | byte
  | word
  | token
  deriving DecidableEq, Repr

def Unit.measureWord (u : Unit) (w : Nat) : Nat :=
  match u with
  | .byte => w
  | .word => w
  | .token => 1

def isWhitespace (b : Nat) : Bool :=
  b == 32 || b == 9 || b == 10 || b == 13

structure State where
  chunks : List (List Nat)
  start : Nat
  measure : Nat
  deriving Repr

def tokenLen (bs : List Nat) : Nat :=
  match bs with
  | [] => 0
  | b :: rest => if isWhitespace b then 0 else 1 + tokenLen rest

def whitespaceLen (bs : List Nat) : Nat :=
  match bs with
  | [] => 0
  | b :: rest => if isWhitespace b then 1 + whitespaceLen rest else 0

def step (chunkSize : Nat) (u : Unit) (st : State) (bs : List Nat) : State :=
  let word := bs.take (tokenLen bs)
  let afterWhitespace := bs.drop (tokenLen bs + whitespaceLen (bs.drop (tokenLen bs)))
  let wordMeasure := Unit.measureWord u word.length
  if wordMeasure > chunkSize then
    { chunks := if st.measure > 0 ∧ st.start < bs.length then st.chunks ++ [bs.take st.start] else st.chunks,
      start := afterWhitespace.length,
      measure := 0 }
  else if st.measure > 0 ∧ st.measure + wordMeasure > chunkSize then
    { chunks := if st.start < bs.length then st.chunks ++ [bs.take st.start] else st.chunks,
      start := word.length,
      measure := wordMeasure }
  else
    { chunks := st.chunks,
      start := st.start,
      measure := st.measure + wordMeasure }

def splitWords (chunkSize : Nat) (u : Unit) (bs : List Nat) : List (List Nat) :=
  let rec go (st : State) (rest : List Nat) : List (List Nat) :=
    match rest with
    | [] => if st.start < bs.length then st.chunks ++ [bs.drop st.start] else st.chunks
    | _ :: tail =>
        let next := step chunkSize u st rest
        go next tail
  go { chunks := [], start := 0, measure := 0 } bs

def bytesOfText (s : String) : List Nat :=
  s.toList.map (fun c => c.toNat)

def textOfBytes (bs : List Nat) : String :=
  String.ofList (bs.map (fun n => Char.ofNat (n % 256)))

def splitText (chunkSize : Nat) (u : Unit) (s : String) : List String :=
  ((splitWords chunkSize u (bytesOfText s)).map textOfBytes).filter (fun x => x ≠ "")

def concatText (chunks : List String) : String :=
  chunks.foldl (· ++ ·) ""

def concatChunks : List (List Nat) → List Nat
  | [] => []
  | xs :: rest => xs ++ concatChunks rest

theorem tokenLen_eq_zero_of_nil : tokenLen [] = 0 := by
  rfl

theorem whitespaceLen_eq_zero_of_nil : whitespaceLen [] = 0 := by
  rfl

theorem splitWords_nil (chunkSize : Nat) (u : Unit) :
    splitWords chunkSize u [] = [] := by
  rfl

theorem splitWords_total (bs : List Nat) (chunkSize : Nat) (u : Unit) :
    ∃ chunks : List (List Nat), splitWords chunkSize u bs = chunks := by
  refine ⟨splitWords chunkSize u bs, rfl⟩

theorem splitWords_empty_chunks (chunkSize : Nat) (u : Unit) :
    splitWords chunkSize u [] = [] := by
  rfl

theorem splitWords_nonempty_exists (bs : List Nat) (chunkSize : Nat) (u : Unit) :
    splitWords chunkSize u bs ≠ [] ∨ splitWords chunkSize u bs = [] := by
  by_cases h : splitWords chunkSize u bs = []
  · right
    exact h
  · left
    exact h

theorem unit_measure_positive (u : Unit) (w : Nat) :
    Unit.measureWord u w > 0 ∨ w = 0 := by
  cases u with
  | byte =>
      cases w with
      | zero => simp [Unit.measureWord]
      | succ w => simp [Unit.measureWord]
  | word =>
      cases w with
      | zero => simp [Unit.measureWord]
      | succ w => simp [Unit.measureWord]
  | token =>
      simp [Unit.measureWord]

theorem concatChunks_nil : concatChunks [] = [] := by
  rfl

theorem concatChunks_single (xs : List Nat) :
    concatChunks [xs] = xs := by
  simp [concatChunks]

theorem concatChunks_append (xs ys : List (List Nat)) :
    concatChunks (xs ++ ys) = concatChunks xs ++ concatChunks ys := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
      simp [concatChunks, ih]

theorem splitText_total (s : String) (chunkSize : Nat) (u : Unit) :
    ∃ chunks : List String, splitText chunkSize u s = chunks := by
  refine ⟨splitText chunkSize u s, rfl⟩

theorem splitText_empty_exists (chunkSize : Nat) (u : Unit) :
    ∃ chunks : List String, splitText chunkSize u "" = chunks := by
  refine ⟨splitText chunkSize u "", rfl⟩

theorem splitText_chunks_nonempty (chunkSize : Nat) (u : Unit) (s : String) (x : String) :
    x ∈ splitText chunkSize u s → x ≠ "" := by
  intro h
  unfold splitText at h
  exact of_decide_eq_true ((List.mem_filter.mp h).right)

#eval splitText 4 .word "hello world kant"
#eval splitText 2 .token "a b c d e f g h"

end KantSplitter
