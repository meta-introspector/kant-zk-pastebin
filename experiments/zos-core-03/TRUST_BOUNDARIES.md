# Threat model and authority boundaries

Candidate message, signature, artifact, operation and guest result can be invalid, substituted, ambiguous, oversized or replayed. The host pins the key, verifier command, adapter and database path. It derives the principal from trusted lab context. Clients must never control those configuration inputs. There is no identity transport or login protocol in this experiment.

The guest can authenticate a receipt relative to its supplied key and check the pinned fixture contract. It has no SQLite capability. Returning status 1 merely permits the host to stage immutable copies and invoke its separately pinned CORE-02 adapter. That adapter uses OpenSSL against the independently provisioned key and rechecks authority, operation, exact signed bytes and actual artifact digest.

Before writing, the adapter checks SQLite policy and schema under an immediate transaction, looks up the signed domain and request, checks balance and writes exactly one receipt and one effect. The receipt records issuer, authority, signature, message, artifact and operation. Deferred reciprocal foreign keys enforce pairing at commit. Replay rolls back. The compiled adapter and private lab files are trusted host assets. Tests use one synthetic SQLite database, and a separate control DB stays byte-identical. Existing replay, crash recovery and database checks run on fresh copies of the original package.

The public test signing seed exists only to make fixture vectors reproducible. The archived positive vector separately verifies the historical Lean issuer signature. Neither fixture identity represents a real wallet or a production authority.
