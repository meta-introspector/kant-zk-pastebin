# Reconciliation

`RequestProject/Kant/Codec/Reconcile.lean`.

* **compare** — `compareObj` returns EQUIVALENT, DIFFERENT, CONFLICT,
  INCOMPARABLE or INCOMPLETE.  `compareObj_equivalent_iff` says EQUIVALENT
  means the same object, and `compareObj_symm` that the order of the two
  sides does not matter.  `conflict_valid` says a CONFLICT is only ever
  reported when both sides claim VALID and their outputs differ.
* **diff** — `diffVal` produces structured `Difference`s with a path, the
  two sides, a kind and a severity.  `diffVal_nil_iff`: the difference
  list is empty exactly when the values are equal, so a comparison never
  invents or hides a disagreement.
* **resolve** — `Strategy` is prefer_source, prefer_verified, prefer_newer,
  manual, merge or reject.  Conflicts are never silently merged:
  `resolve_reject` produces nothing, `merge_keeps_both` keeps both sides,
  and `resolve_records` puts every resolution into the resulting object's
  provenance.
