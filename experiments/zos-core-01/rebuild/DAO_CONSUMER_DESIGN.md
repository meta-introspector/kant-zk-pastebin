# Synthetic DAO consumer

Verify the signature using the independently pinned public key. Require
an allowed requested action separately, compare signed context with the
pinned descriptor and requested operation, and independently hash exact
artifact bytes. Reject a consumed request. The synthetic policy allows
debit 7 and debit 8 and denies mint. The adapter issues only debit 7.

Changes occur only after validation. Complete state is balance, consumed
flag, replay-record count and audit log. Every rejection compares the
complete state with its snapshot, including the counter and log.
