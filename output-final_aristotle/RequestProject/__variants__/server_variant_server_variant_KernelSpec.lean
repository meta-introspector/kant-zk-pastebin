/-
# The extracted kernel computes the Kant definitions

`RequestProject.Wasm.Kernel` expresses the pastebin's hot paths in the
verified wasm fragment, and `RequestProject.Wasm.Semantics` shows that the
compiled instructions evaluate to the value of those expressions.  What is
still missing is the link to the Lean development itself: that the wasm
functions compute the *same* numbers as `Kant.Bytes.hexDigit`,
`Kant.Dasl.mkCid`, `Kant.Credits.creditsFor`, and so on.

That is what this module proves — one theorem per exported function.
Together with `Expr.exec_compile` (the compiled code evaluates the
expression) and `Encode.module` (the bytes are the binary format of that
code), this is the correctness statement for the extraction:

  Lean definition  =  wasm expression  =  emitted `.wasm` function.

Arguments and results are `UInt64`, whose arithmetic is exactly wasm's
`i64` arithmetic; hypotheses such as `x.toNat < 16` record where a
function is only meant to be called on a restricted range, and where a
64-bit result would otherwise wrap.
-/
import Mathlib
import RequestProject.Wasm.Kernel
import RequestProject.Wasm.Semantics
import RequestProject.Kant.Bytes
import RequestProject.Kant.Dasl
import RequestProject.Kant.Credits
import RequestProject.Kant.Sneakernet
import RequestProject.Kant.Stego

set_option autoImplicit false
set_option relaxedAutoImplicit false
set_option maxRecDepth 8000

namespace Kant.Wasm.Kernel

open Kant.Wasm Kant.Wasm.Expr

/-! ## Helpers -/

theorem toNat_ofNat_of_lt {k : Nat} (h : k < 2 ^ 64) : (UInt64.ofNat k).toNat = k := by
  have h' : k < 18446744073709551616 := by omega
  simp [h']

/-! ## `hex_digit` -/

theorem hexDigit_toNat {n : Nat} (h : n < 16) :
    (Kant.Bytes.hexDigit n).toNat = if n < 10 then 48 + n else 87 + n := by
  interval_cases n <;> rfl

/-- The hex-digit template computes `Kant.Bytes.hexDigit` of whatever
sub-expression it is applied to. -/
theorem eval_hexDigitOf {locals : List UInt64} {e : Expr} {v : UInt64}
    (hv : Expr.eval locals e = some v) (h : v.toNat < 16) :
    (Expr.eval locals (hexDigitOf e)).map UInt64.toNat
      = some (Kant.Bytes.hexDigit v.toNat).toNat := by
  have h39 : (39 : UInt64).toNat = 39 := rfl
  rw [hexDigit_toNat h]
  simp [hexDigitOf, add, mul, Expr.eval, BinOp.apply, CmpOp.apply, UInt64.toNat_add,
    UInt64.le_iff_toNat_le, hv]
  split_ifs <;> simp only [h39, UInt64.toNat_ofNat] <;> omega

/-- The exported `hex_digit` computes `Kant.Bytes.hexDigit`. -/
theorem eval_hexDigitE (x : UInt64) (h : x.toNat < 16) :
    (Expr.eval [x] hexDigitE).map UInt64.toNat
      = some (Kant.Bytes.hexDigit x.toNat).toNat :=
  eval_hexDigitOf (by simp [Expr.eval]) h

/-- The exported `hex_hi` computes the first digit of `Kant.Bytes.hexByte`. -/
theorem eval_hexHiE (b : UInt64) (h : b.toNat < 256) :
    (Expr.eval [b] hexHiE).map UInt64.toNat
      = some (Kant.Bytes.hexDigit (b.toNat / 16)).toNat := by
  have hd : (b / UInt64.ofNat 16).toNat = b.toNat / 16 := by
    rw [UInt64.toNat_div, toNat_ofNat_of_lt (by omega)]
  have hv : Expr.eval [b] (divC (var 0) 16) = some (b / UInt64.ofNat 16) := by
    simp [divC, Expr.eval, BinOp.apply]
  have hlt : (b / UInt64.ofNat 16).toNat < 16 := by rw [hd]; omega
  have := eval_hexDigitOf hv hlt
  rwa [hd] at this

/-- The exported `hex_lo` computes the second digit of `Kant.Bytes.hexByte`. -/
theorem eval_hexLoE (b : UInt64) :
    (Expr.eval [b] hexLoE).map UInt64.toNat
      = some (Kant.Bytes.hexDigit (b.toNat % 16)).toNat := by
  have hd : (b % UInt64.ofNat 16).toNat = b.toNat % 16 := by
    rw [UInt64.toNat_mod, toNat_ofNat_of_lt (by omega)]
  have hv : Expr.eval [b] (modC (var 0) 16) = some (b % UInt64.ofNat 16) := by
    simp [modC, Expr.eval, BinOp.apply]
  have hlt : (b % UInt64.ofNat 16).toNat < 16 := by rw [hd]; omega
  have := eval_hexDigitOf hv hlt
  rwa [hd] at this

/-- Both hex digits of a byte, as `Kant.Bytes.hexByte` lists them. -/
theorem hexByte_eq (x : UInt8) :
    Kant.Bytes.hexByte x
      = [Kant.Bytes.hexDigit (x.toNat / 16), Kant.Bytes.hexDigit (x.toNat % 16)] := rfl

/-! ## The FNV-1a digest -/

/-- The exported `fnv_offset` is the FNV-1a offset basis. -/
theorem eval_fnvOffsetE : Expr.eval [] fnvOffsetE = some Kant.Bytes.fnvOffset := by
  simp [fnvOffsetE, add, mul, Expr.eval, BinOp.apply, Kant.Bytes.fnvOffset]

/-- The exported `fnv1a_step` computes `Kant.Bytes.fnvStep`. -/
theorem eval_fnvStepE (h b : UInt64) (hb : b.toNat < 256) :
    Expr.eval [h, b] fnvStepE = some (Kant.Bytes.fnvStep h b.toUInt8) := by
  have hbb : b.toUInt8.toUInt64 = b := by
    have hmod : b % 256 = b := UInt64.mod_eq_of_lt hb
    simpa using hmod
  simp [fnvStepE, mul, Expr.xor, Expr.eval, BinOp.apply, Kant.Bytes.fnvStep,
    Kant.Bytes.fnvPrime, fnvPrimeConst, hbb]

/-- The exported `u64_byte` computes the big-endian byte expansion
`Kant.Bytes.u64Bytes`. -/
theorem eval_u64ByteE (x i : UInt64) (hi : i.toNat < 8) :
    (Expr.eval [x, i] u64ByteE).map UInt64.toNat
      = some ((Kant.Bytes.u64Bytes x)[i.toNat]'(by simp [hi])).toNat := by
  have h7 : (7 : UInt64).toNat = 7 := rfl
  have h8 : (8 : UInt64).toNat = 8 := rfl
  have hsub : ((7 : UInt64) - i).toNat = 7 - i.toNat := by
    rw [UInt64.toNat_sub, h7]; omega
  have hshift : ((8 : UInt64) * ((7 : UInt64) - i)) = UInt64.ofNat (8 * (7 - i.toNat)) := by
    apply UInt64.toNat.inj
    rw [UInt64.toNat_mul, hsub, h8, toNat_ofNat_of_lt (by omega)]
    omega
  have hand : ∀ n : Nat, n &&& 255 = n % 256 := by
    intro n
    have := Nat.and_two_pow_sub_one_eq_mod n 8
    simpa using this
  simp only [Kant.Bytes.u64Bytes, List.getElem_map, List.getElem_range]
  simp [u64ByteE, andE, mul, sub, Expr.eval, BinOp.apply, hshift,
    UInt64.toNat_and, UInt64.toNat_toUInt8, hand]

/-- The exported `cantor_pair` computes `Nat.pair`, the pairing the Gödel
numbering of code movies is built from, on 31-bit inputs. -/
theorem eval_cantorPairE (a b : UInt64) (ha : a.toNat < 2 ^ 31) (hb : b.toNat < 2 ^ 31) :
    (Expr.eval [a, b] cantorPairE).map UInt64.toNat
      = some (Nat.pair a.toNat b.toNat) := by
  norm_num at ha hb
  have h1 : a.toNat * a.toNat + a.toNat + b.toNat < 18446744073709551616 := by nlinarith
  have h2 : b.toNat * b.toNat + a.toNat < 18446744073709551616 := by nlinarith
  simp [cantorPairE, add, mul, Expr.eval, BinOp.apply, CmpOp.apply, UInt64.toNat_add,
    UInt64.lt_iff_toNat_lt, UInt64.le_iff_toNat_le, Nat.pair]
  split_ifs with h <;> simp <;> omega

/-! ## DASL addresses -/

/-- The exported `cid_prefix` computes `Kant.Dasl.cidPrefix`. -/
theorem eval_cidPrefixE (x : UInt64) :
    (Expr.eval [x] cidPrefixE).map UInt64.toNat = some (Kant.Dasl.cidPrefix x.toNat) := by
  simp [cidPrefixE, divC, Expr.eval, BinOp.apply, UInt64.toNat_div, Kant.Dasl.cidPrefix]

/-- The exported `cid_type` computes `Kant.Dasl.cidType`. -/
theorem eval_cidTypeE (x : UInt64) :
    (Expr.eval [x] cidTypeE).map UInt64.toNat = some (Kant.Dasl.cidType x.toNat) := by
  simp [cidTypeE, divC, modC, Expr.eval, BinOp.apply, UInt64.toNat_div, UInt64.toNat_mod,
    Kant.Dasl.cidType]

/-- The exported `cid_payload` computes `Kant.Dasl.cidPayload`. -/
theorem eval_cidPayloadE (x : UInt64) :
    (Expr.eval [x] cidPayloadE).map UInt64.toNat = some (Kant.Dasl.cidPayload x.toNat) := by
  simp [cidPayloadE, modC, Expr.eval, BinOp.apply, UInt64.toNat_mod, Kant.Dasl.cidPayload]

/-- The exported `mk_cid` computes `Kant.Dasl.mkCid` on well-formed fields. -/
theorem eval_mkCidE (t p : UInt64) (ht : t.toNat < 16) (hp : p.toNat < 2 ^ 44) :
    (Expr.eval [t, p] mkCidE).map UInt64.toNat
      = some (Kant.Dasl.mkCid t.toNat p.toNat) := by
  norm_num at hp
  simp [mkCidE, add, mul, Expr.eval, BinOp.apply, UInt64.toNat_add, UInt64.toNat_mul,
    Kant.Dasl.mkCid, Kant.Dasl.daslPrefix, daslPrefix]
  omega

/-- The exported `merge_cids` computes `Kant.Dasl.mergeCids`, for all inputs. -/
theorem eval_mergeCidsE (a b : UInt64) :
    (Expr.eval [a, b] mergeCidsE).map UInt64.toNat
      = some (Kant.Dasl.mergeCids a.toNat b.toNat) := by
  have hx := Nat.xor_lt_two_pow (n := 48)
    (Nat.mod_lt a.toNat (by positivity : (0:ℕ) < 2 ^ 48))
    (Nat.mod_lt b.toNat (by positivity : (0:ℕ) < 2 ^ 48))
  norm_num at hx
  simp [mergeCidsE, add, mul, Expr.xor, modC, Expr.eval, BinOp.apply, UInt64.toNat_add,
    UInt64.toNat_mod, UInt64.toNat_xor, Kant.Dasl.mergeCids, Kant.Dasl.daslPrefix, daslPrefix]
  omega

/-! ## Credits and stego capacity -/

/-- The exported `credits_for` computes `Kant.Credits.creditsFor`. -/
theorem eval_creditsForE (x : UInt64) :
    (Expr.eval [x] creditsForE).map UInt64.toNat
      = some (Kant.Credits.creditsFor x.toNat) := by
  simp [creditsForE, divC, Expr.eval, BinOp.apply, UInt64.toNat_div, Kant.Credits.creditsFor]

/-- The exported `capacity_bytes` computes `Kant.Stego.capacityBytes`. -/
theorem eval_capacityBytesE (cs : Kant.Stego.Carrier) (x : UInt64) (h : x.toNat = cs.length) :
    (Expr.eval [x] capacityBytesE).map UInt64.toNat
      = some (Kant.Stego.capacityBytes cs) := by
  simp [capacityBytesE, divC, Expr.eval, BinOp.apply, UInt64.toNat_div,
    Kant.Stego.capacityBytes, h]

/-! ## The 5 MB social-export bound -/

/-- The chunker produces exactly `⌈len / limit⌉` pieces. -/
theorem chunk_length_eq (limit : Nat) (hlim : 0 < limit) (data : Kant.Bytes.Blob) :
    (Kant.Sneakernet.chunk limit data).length = (data.length + limit - 1) / limit := by
  induction data using Kant.Sneakernet.chunk.induct limit with
  | case1 => omega
  | case2 data hz hlen hempty =>
      rw [Kant.Sneakernet.chunk, if_neg hz, if_pos hlen, if_pos hempty]
      have hd : data.length = 0 := by simpa using List.isEmpty_iff.mp hempty
      rw [hd]
      simp only [List.length_nil, Nat.zero_add]
      exact (Nat.div_eq_of_lt (by omega)).symm
  | case3 data hz hlen hempty =>
      rw [Kant.Sneakernet.chunk, if_neg hz, if_pos hlen, if_neg hempty]
      have hpos : 0 < data.length := by
        rcases data with _ | ⟨d, ds⟩
        · simp at hempty
        · simp
      have hdiv : (data.length + limit - 1) / limit = 1 :=
        Nat.div_eq_of_lt_le (by omega) (by omega)
      simp [hdiv]
  | case4 data hz hlen ih =>
      rw [Kant.Sneakernet.chunk, if_neg hz, if_neg hlen]
      simp only [List.length_cons, ih, List.length_drop]
      have e1 : data.length - limit + limit - 1 = data.length - 1 := by omega
      have e2 : data.length + limit - 1 = data.length - 1 + limit := by omega
      rw [e1, e2, Nat.add_div_right _ hlim]

/-- The exported `social_chunks` counts the pieces the 5 MB chunker
produces (assuming the payload length does not overflow 64 bits). -/
theorem eval_socialChunksE (data : Kant.Bytes.Blob) (x : UInt64) (h : x.toNat = data.length)
    (hb : data.length + Kant.Sneakernet.socialLimit - 1 < 2 ^ 64) :
    (Expr.eval [x] socialChunksE).map UInt64.toNat
      = some (Kant.Sneakernet.chunk Kant.Sneakernet.socialLimit data).length := by
  rw [chunk_length_eq _ (by simp [Kant.Sneakernet.socialLimit]) data]
  have heval : (Expr.eval [x] socialChunksE)
      = some ((x + UInt64.ofNat 5242879) / UInt64.ofNat 5242880) := by
    simp [socialChunksE, add, divC, Expr.eval, BinOp.apply, Kant.Wasm.Kernel.socialLimit]
  have hc1 : (UInt64.ofNat 5242879).toNat = 5242879 := toNat_ofNat_of_lt (by omega)
  have hc2 : (UInt64.ofNat 5242880).toNat = 5242880 := toNat_ofNat_of_lt (by omega)
  simp only [Kant.Sneakernet.socialLimit] at hb ⊢
  have hsum : (data.length + 5242879) % 18446744073709551616 = data.length + 5242879 :=
    Nat.mod_eq_of_lt (by omega)
  have hlim : 5 * 1024 * 1024 = 5242880 := by norm_num
  have hshift : data.length + 5242880 - 1 = data.length + 5242879 := by omega
  rw [heval]
  simp only [Option.map_some, UInt64.toNat_div, UInt64.toNat_add, hc1, hc2, h]
  rw [hsum, hlim, hshift]

/-- The exported `fits_social` decides the 5 MB social-export bound. -/
theorem eval_fitsSocialE (x : UInt64) :
    (Expr.eval [x] fitsSocialE).map UInt64.toNat
      = some (if x.toNat ≤ Kant.Sneakernet.socialLimit then 1 else 0) := by
  simp [fitsSocialE, Expr.eval, CmpOp.apply, Kant.Sneakernet.socialLimit,
    Kant.Wasm.Kernel.socialLimit, UInt64.le_iff_toNat_le]
  split <;> rfl

/-! ## Stego least-significant-bit writes -/

/-- The exported `lsb_embed` performs one step of `Kant.Stego.embedBits`. -/
theorem eval_lsbEmbedE (s b : UInt64) (bit : Bool) (hb : b.toNat = if bit then 1 else 0) :
    (Expr.eval [s, b] lsbEmbedE).map UInt64.toNat
      = some ((Kant.Stego.embedBits [s.toNat] [bit]).headD 0) := by
  have hs : s.toNat < 2 ^ 64 := s.toNat_lt_size
  norm_num at hs
  simp [lsbEmbedE, add, mul, divC, modC, Expr.eval, BinOp.apply, UInt64.toNat_add,
    UInt64.toNat_mul, UInt64.toNat_div, UInt64.toNat_mod, Kant.Stego.embedBits, hb]
  cases bit <;> simp <;> omega

/-- The exported `lsb_extract` performs one step of `Kant.Stego.extractBits`. -/
theorem eval_lsbExtractE (s : UInt64) :
    (Expr.eval [s] lsbExtractE).map (fun v => v.toNat % 2 == 1)
      = some ((Kant.Stego.extractBits 1 [s.toNat]).headD false) := by
  simp [lsbExtractE, modC, Expr.eval, BinOp.apply, UInt64.toNat_mod, Kant.Stego.extractBits]

/-! ## The orbifold action -/

/-- The exported `rotate71` performs `Kant.Dasl.rotate71`. -/
theorem eval_rotate71E (o : Kant.Dasl.Orbifold) (l k : UInt64) (hl : l.toNat = o.l)
    (hsum : o.l + k.toNat < 2 ^ 64) :
    (Expr.eval [l, k] rotate71E).map UInt64.toNat
      = some (Kant.Dasl.rotate71 o k.toNat).l := by
  norm_num at hsum
  simp [rotate71E, add, modC, Expr.eval, BinOp.apply, UInt64.toNat_add, UInt64.toNat_mod,
    Kant.Dasl.rotate71, hl]
  omega

/-- The exported `reflect59` performs `Kant.Dasl.reflect59`. -/
theorem eval_reflect59E (o : Kant.Dasl.Orbifold) (m k : UInt64) (hm : m.toNat = o.m)
    (hsum : o.m + k.toNat < 2 ^ 64) :
    (Expr.eval [m, k] reflect59E).map UInt64.toNat
      = some (Kant.Dasl.reflect59 o k.toNat).m := by
  norm_num at hsum
  simp [reflect59E, add, modC, Expr.eval, BinOp.apply, UInt64.toNat_add, UInt64.toNat_mod,
    Kant.Dasl.reflect59, hm]
  omega

/-- The exported `dual47` performs `Kant.Dasl.dual47`. -/
theorem eval_dual47E (o : Kant.Dasl.Orbifold) (n k : UInt64) (hn : n.toNat = o.n)
    (hsum : o.n + k.toNat < 2 ^ 64) :
    (Expr.eval [n, k] dual47E).map UInt64.toNat
      = some (Kant.Dasl.dual47 o k.toNat).n := by
  norm_num at hsum
  simp [dual47E, add, modC, Expr.eval, BinOp.apply, UInt64.toNat_add, UInt64.toNat_mod,
    Kant.Dasl.dual47, hn]
  omega

end Kant.Wasm.Kernel
