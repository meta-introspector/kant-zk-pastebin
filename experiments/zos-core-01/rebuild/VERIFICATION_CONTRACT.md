# Verification contract

The descriptor uses fixed ASCII lines terminated by LF, including the last
line. The domain is zos.core01b.descriptor.v1. Ordered fields are job,
commit, toolchain, module, target, reference, proposition, policy,
replay-domain, request, operation, checker-sha256, source-sha256,
reference-source-sha256, artifact-sha256, reference-artifact-sha256 and
lean-binary-sha256. Field lines use key=value. Hashes are lowercase SHA-256.
The only admissible request is byte-equal to the pinned fixture descriptor.

The receipt signs the complete descriptor after these three LF-terminated
lines: zos.core01b.receipt.v1, verdict=accepted, and
basis=source-compiled-jobverifier-fixture. The signature is detached Ed25519.

Build Ref and Good with Lean -o. Run Lean --run Check.lean --module Good
--decl target --ref Ref --expected expected from the private LEAN_PATH.
Acceptance requires exact empty-axiom acceptance JSON, exit zero and empty
stderr. Reject SORRY, indeterminate outcomes and process failure. The
checker verifies theorem ownership, structural type and universe agreement,
and axiom policy in the imported environment. This uses a source-compiled
fixture and does not independently replay external oleans.
