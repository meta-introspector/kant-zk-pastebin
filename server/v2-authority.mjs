import crypto from "node:crypto";
import { DatabaseSync } from "node:sqlite";

/*
 * Experimental V2 authority module.
 *
 * No legacy credential is interpreted as a V2 token.
 * The operator verification key must come from trusted
 * configuration, never from an incoming request.
 *
 * This module does not authenticate the human operator
 * or the room owner's entitlement.
 */

const ROOM = /^[0-9a-f]{64}$/;
const TOKEN_ID = /^[0-9a-f]{32}$/;

function exactKeys(value, names) {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join(",") ===
      [...names].sort().join(",");
}

function b64decode(value, length = null) {
  if (typeof value !== "string") return null;

  try {
    const bytes = Buffer.from(value, "base64url");

    if (
      bytes.toString("base64url") !== value ||
      (length !== null && bytes.length !== length)
    ) return null;

    return bytes;
  } catch {
    return null;
  }
}

function keyFromDer(encoded) {
  const bytes = b64decode(encoded);
  if (!bytes) return null;

  try {
    const key = crypto.createPublicKey({
      key: bytes,
      format: "der",
      type: "spki"
    });

    if (key.asymmetricKeyType !== "ed25519") {
      return null;
    }

    const canonical = key.export({
      format: "der",
      type: "spki"
    });

    if (!canonical.equals(bytes)) return null;

    return key;
  } catch {
    return null;
  }
}

function payload(domain, fields) {
  return Buffer.from(
    JSON.stringify([domain, ...fields]),
    "utf8"
  );
}

function verify(key, data, encodedSignature) {
  const signature = b64decode(encodedSignature, 64);

  if (!key || !signature) return false;

  try {
    return crypto.verify(
      null, data, key, signature
    );
  } catch {
    return false;
  }
}

export function publicKeyEncoding(key) {
  return key.export({
    format: "der",
    type: "spki"
  }).toString("base64url");
}

export function createEnrollment(
  operatorPrivateKey, room, issuerPublicKey
) {
  const claims = {
    version: 2,
    room,
    issuerPublicKey: publicKeyEncoding(issuerPublicKey),
    epoch: 1
  };

  return {
    ...claims,
    signature: crypto.sign(
      null,
      payload("kant-enrollment-v2", [
        claims.room,
        claims.issuerPublicKey,
        claims.epoch
      ]),
      operatorPrivateKey
    ).toString("base64url")
  };
}

export function createToken(
  issuerPrivateKey, room, id, limit, epoch = 1
) {
  const claims = {
    version: 2,
    room,
    id,
    limit,
    epoch
  };

  return {
    ...claims,
    signature: crypto.sign(
      null,
      payload("kant-publish-v2", [
        room, id, limit, epoch
      ]),
      issuerPrivateKey
    ).toString("base64url")
  };
}


/**
 * Experimental offline rotation manifest.
 *
 * Both the pinned operator and the CURRENT issuer
 * must authorize the exact transition.
 *
 * Never expose private signing keys to recipients.
 */
export function createRotation(
  operatorPrivateKey,
  oldIssuerPrivateKey,
  room,
  oldIssuerPublicKey,
  newIssuerPublicKey,
  fromEpoch,
) {
  if (
    !Number.isSafeInteger(fromEpoch) ||
    fromEpoch < 1 ||
    fromEpoch >= Number.MAX_SAFE_INTEGER
  ) {
    throw new Error("INVALID_ROTATION_EPOCH");
  }

  const claims = {
    version: 2,
    room,
    oldIssuerPublicKey:
      publicKeyEncoding(oldIssuerPublicKey),
    newIssuerPublicKey:
      publicKeyEncoding(newIssuerPublicKey),
    fromEpoch,
    toEpoch: fromEpoch + 1
  };

  const data = payload("kant-rotation-v2", [
    claims.room,
    claims.oldIssuerPublicKey,
    claims.newIssuerPublicKey,
    claims.fromEpoch,
    claims.toEpoch
  ]);

  return {
    ...claims,
    operatorSignature: crypto.sign(
      null, data, operatorPrivateKey
    ).toString("base64url"),
    issuerSignature: crypto.sign(
      null, data, oldIssuerPrivateKey
    ).toString("base64url")
  };
}

export class V2Authority {
  constructor(dbPath, operatorPublicKey) {
    if (
      !operatorPublicKey ||
      operatorPublicKey.asymmetricKeyType !== "ed25519"
    ) {
      throw new Error("TRUSTED_OPERATOR_KEY_REQUIRED");
    }

    this.operatorKey = operatorPublicKey;
    this.db = new DatabaseSync(dbPath);

    this.db.exec("PRAGMA busy_timeout = 2500");

    this.db.exec(`
      CREATE TABLE IF NOT EXISTS v2_rooms (
        room TEXT PRIMARY KEY,
        issuer_key TEXT NOT NULL,
        epoch INTEGER NOT NULL CHECK(epoch > 0)
      );

      CREATE TABLE IF NOT EXISTS v2_spends (
        room TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        token_id TEXT NOT NULL,
        limit_max INTEGER NOT NULL CHECK(limit_max > 0),
        spent INTEGER NOT NULL DEFAULT 0 CHECK(spent >= 0),
        PRIMARY KEY(room, epoch, token_id)
      );
    `);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS v2_outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        publication_id TEXT NOT NULL UNIQUE,
        room TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        token_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        line_count INTEGER NOT NULL
          CHECK(line_count > 0 AND line_count <= 100),
        created_at TEXT NOT NULL
          DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS
        v2_outbox_room_sequence
      ON v2_outbox(room, sequence);
    `);
  }

  close() {
    this.db.close();
  }

  isProtected(room) {
    return Boolean(this.db.prepare(`
      SELECT 1 FROM v2_rooms WHERE room = ?
    `).get(room));
  }

  verifyEnrollment(manifest) {
    if (!exactKeys(manifest, [
      "version", "room", "issuerPublicKey",
      "epoch", "signature"
    ])) return false;

    if (
      manifest.version !== 2 ||
      !ROOM.test(manifest.room) ||
      manifest.epoch !== 1
    ) return false;

    if (!keyFromDer(manifest.issuerPublicKey)) {
      return false;
    }

    return verify(
      this.operatorKey,
      payload("kant-enrollment-v2", [
        manifest.room,
        manifest.issuerPublicKey,
        manifest.epoch
      ]),
      manifest.signature
    );
  }

  enroll(manifest) {
    if (!this.verifyEnrollment(manifest)) {
      return { ok: false, error: "bad enrollment" };
    }

    this.db.exec("BEGIN IMMEDIATE");
    let active = true;

    try {
      const result = this.db.prepare(`
        INSERT INTO v2_rooms(room, issuer_key, epoch)
        VALUES (?, ?, 1)
        ON CONFLICT(room) DO NOTHING
      `).run(
        manifest.room,
        manifest.issuerPublicKey
      );

      if (result.changes !== 1) {
        this.db.exec("ROLLBACK");
        active = false;
        return {
          ok: false,
          error: "room already registered"
        };
      }

      this.db.exec("COMMIT");
      active = false;

      return { ok: true };
    } catch (error) {
      if (active && this.db.isTransaction) {
        this.db.exec("ROLLBACK");
      }
      throw error;
    }
  }

  verifyToken(token, room, authority) {
    if (!exactKeys(token, [
      "version", "room", "id", "limit",
      "epoch", "signature"
    ])) return false;

    if (
      token.version !== 2 ||
      token.room !== room ||
      !ROOM.test(room) ||
      !TOKEN_ID.test(token.id) ||
      !Number.isSafeInteger(token.limit) ||
      token.limit < 1 ||
      !Number.isSafeInteger(token.epoch) ||
      token.epoch !== authority?.epoch
    ) return false;

    const issuerKey = keyFromDer(
      authority.issuer_key
    );

    return verify(
      issuerKey,
      payload("kant-publish-v2", [
        token.room,
        token.id,
        token.limit,
        token.epoch
      ]),
      token.signature
    );
  }

  rotate(manifest) {
    if (!exactKeys(manifest, [
      "version",
      "room",
      "oldIssuerPublicKey",
      "newIssuerPublicKey",
      "fromEpoch",
      "toEpoch",
      "operatorSignature",
      "issuerSignature"
    ])) {
      return { ok: false, error: "invalid manifest" };
    }

    if (
      manifest.version !== 2 ||
      typeof manifest.room !== "string" ||
      !ROOM.test(manifest.room) ||
      !Number.isSafeInteger(manifest.fromEpoch) ||
      manifest.fromEpoch < 1 ||
      manifest.fromEpoch >= Number.MAX_SAFE_INTEGER ||
      manifest.toEpoch !== manifest.fromEpoch + 1 ||
      typeof manifest.oldIssuerPublicKey !== "string" ||
      typeof manifest.newIssuerPublicKey !== "string" ||
      manifest.oldIssuerPublicKey ===
        manifest.newIssuerPublicKey
    ) {
      return { ok: false, error: "invalid rotation" };
    }

    const oldKey = keyFromDer(
      manifest.oldIssuerPublicKey
    );

    const newKey = keyFromDer(
      manifest.newIssuerPublicKey
    );

    if (!oldKey || !newKey) {
      return { ok: false, error: "invalid key" };
    }

    const signed = payload("kant-rotation-v2", [
      manifest.room,
      manifest.oldIssuerPublicKey,
      manifest.newIssuerPublicKey,
      manifest.fromEpoch,
      manifest.toEpoch
    ]);

    if (
      !verify(
        this.operatorKey,
        signed,
        manifest.operatorSignature
      ) ||
      !verify(
        oldKey,
        signed,
        manifest.issuerSignature
      )
    ) {
      return { ok: false, error: "unauthorized rotation" };
    }

    this.db.exec("BEGIN IMMEDIATE");
    let active = true;

    try {
      const current = this.db.prepare(`
        SELECT issuer_key, epoch
        FROM v2_rooms
        WHERE room = ?
      `).get(manifest.room);

      if (
        !current ||
        current.issuer_key !==
          manifest.oldIssuerPublicKey ||
        current.epoch !== manifest.fromEpoch
      ) {
        this.db.exec("ROLLBACK");
        active = false;

        return { ok: false, error: "stale authority" };
      }

      const result = this.db.prepare(`
        UPDATE v2_rooms
        SET issuer_key = ?, epoch = ?
        WHERE room = ?
          AND issuer_key = ?
          AND epoch = ?
      `).run(
        manifest.newIssuerPublicKey,
        manifest.toEpoch,
        manifest.room,
        manifest.oldIssuerPublicKey,
        manifest.fromEpoch
      );

      if (result.changes !== 1) {
        this.db.exec("ROLLBACK");
        active = false;
        return { ok: false, error: "rotation conflict" };
      }

      this.db.exec("COMMIT");
      active = false;

      return { ok: true, epoch: manifest.toEpoch };

    } catch (error) {
      if (active && this.db.isTransaction) {
        try {
          this.db.exec("ROLLBACK");
        } catch (rollbackError) {
          error.rollbackError = rollbackError;
        }
      }
      throw error;
    }
  }

  validate(token, room) {
    const authority = this.db.prepare(`
      SELECT issuer_key, epoch
      FROM v2_rooms WHERE room = ?
    `).get(room);

    return Boolean(
      authority &&
      this.verifyToken(token, room, authority)
    );
  }


  /**
   * Experimental atomic quota + durable publication.
   *
   * This method does not publish to the in-memory Rooms
   * instance. The durable outbox is the persistent source.
   *
   * publicationId is an immutable idempotency key.
   */
  admitDurable(token, room, lines, publicationId) {
    if (
      !Array.isArray(lines) ||
      lines.length < 1 ||
      lines.length > 100 ||
      !lines.every(
        line =>
          typeof line === "string" &&
          line.length > 0 &&
          Buffer.byteLength(line, "utf8") <= 4096
      ) ||
      typeof publicationId !== "string" ||
      !/^[0-9a-f]{32}$/.test(publicationId)
    ) {
      return {
        ok: false,
        status: 400,
        error: "invalid durable publication"
      };
    }

    const payloadJson = JSON.stringify(lines);

    if (Buffer.byteLength(payloadJson, "utf8") > 65536) {
      return {
        ok: false,
        status: 400,
        error: "publication too large"
      };
    }

    this.db.exec("BEGIN IMMEDIATE");
    let active = true;

    try {
      const authority = this.db.prepare(`
        SELECT issuer_key, epoch
        FROM v2_rooms
        WHERE room = ?
      `).get(room);

      if (
        !authority ||
        !this.verifyToken(token, room, authority)
      ) {
        this.db.exec("ROLLBACK");
        active = false;

        return {
          ok: false,
          status: 401,
          error: "invalid v2 authority"
        };
      }

      const previous = this.db.prepare(`
        SELECT sequence, room, epoch, token_id,
               payload_json, line_count
        FROM v2_outbox
        WHERE publication_id = ?
      `).get(publicationId);

      if (previous) {
        const identical = (
          previous.room === room &&
          previous.epoch === token.epoch &&
          previous.token_id === token.id &&
          previous.payload_json === payloadJson &&
          previous.line_count === lines.length
        );

        this.db.exec("ROLLBACK");
        active = false;

        if (!identical) {
          return {
            ok: false,
            status: 409,
            error: "publication identity conflict"
          };
        }

        return {
          ok: true,
          status: 200,
          duplicate: true,
          sequence: previous.sequence
        };
      }

      this.db.prepare(`
        INSERT INTO v2_spends
          (room, epoch, token_id, limit_max, spent)
        VALUES (?, ?, ?, ?, 0)
        ON CONFLICT(room, epoch, token_id)
        DO NOTHING
      `).run(
        room, token.epoch, token.id, token.limit
      );

      const updated = this.db.prepare(`
        UPDATE v2_spends
        SET spent = spent + ?
        WHERE room = ?
          AND epoch = ?
          AND token_id = ?
          AND limit_max = ?
          AND spent <= limit_max - ?
      `).run(
        lines.length,
        room,
        token.epoch,
        token.id,
        token.limit,
        lines.length
      );

      if (updated.changes !== 1) {
        this.db.exec("ROLLBACK");
        active = false;

        return {
          ok: false,
          status: 429,
          error: "v2 pass exhausted"
        };
      }

      const inserted = this.db.prepare(`
        INSERT INTO v2_outbox
          (publication_id, room, epoch, token_id,
           payload_json, line_count)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        publicationId,
        room,
        token.epoch,
        token.id,
        payloadJson,
        lines.length
      );

      const spend = this.db.prepare(`
        SELECT spent, limit_max
        FROM v2_spends
        WHERE room = ? AND epoch = ? AND token_id = ?
      `).get(room, token.epoch, token.id);

      this.db.exec("COMMIT");
      active = false;

      return {
        ok: true,
        status: 200,
        duplicate: false,
        sequence: Number(inserted.lastInsertRowid),
        remaining: spend.limit_max - spend.spent
      };

    } catch (error) {
      if (active && this.db.isTransaction) {
        try {
          this.db.exec("ROLLBACK");
        } catch (rollbackError) {
          error.rollbackError = rollbackError;
        }
      }
      throw error;
    }
  }

  /**
   * Read durable publications in committed sequence order.
   * The cursor is a global SQLite sequence, filtered by room.
   * Sequence gaps are permitted.
   */
  readDurable(room, cursor = 0, limit = 100) {
    if (
      typeof room !== "string" ||
      !ROOM.test(room) ||
      !Number.isSafeInteger(cursor) ||
      cursor < 0 ||
      !Number.isSafeInteger(limit) ||
      limit < 1 ||
      limit > 100
    ) {
      throw new Error("INVALID_OUTBOX_READ");
    }

    return this.db.prepare(`
      SELECT sequence, publication_id, room,
             epoch, token_id, payload_json, line_count
      FROM v2_outbox
      WHERE room = ? AND sequence > ?
      ORDER BY sequence ASC
      LIMIT ?
    `).all(room, cursor, limit).map(row => ({
      sequence: row.sequence,
      publicationId: row.publication_id,
      room: row.room,
      epoch: row.epoch,
      tokenId: row.token_id,
      lines: JSON.parse(row.payload_json),
      lineCount: row.line_count
    }));
  }

  admit(token, room, lines = 1) {
    if (
      !Number.isSafeInteger(lines) ||
      lines < 1 ||
      lines > 100000
    ) {
      return {
        ok: false,
        status: 400,
        error: "invalid line count"
      };
    }

    this.db.exec("BEGIN IMMEDIATE");
    let active = true;

    try {
      const authority = this.db.prepare(`
        SELECT issuer_key, epoch
        FROM v2_rooms
        WHERE room = ?
      `).get(room);

      if (!authority ||
          !this.verifyToken(token, room, authority)) {
        this.db.exec("ROLLBACK");
        active = false;
        return {
          ok: false,
          status: 401,
          error: "invalid v2 authority"
        };
      }

      this.db.prepare(`
        INSERT INTO v2_spends
          (room, epoch, token_id, limit_max, spent)
        VALUES (?, ?, ?, ?, 0)
        ON CONFLICT(room, epoch, token_id)
        DO NOTHING
      `).run(
        room, token.epoch, token.id, token.limit
      );

      const updated = this.db.prepare(`
        UPDATE v2_spends
        SET spent = spent + ?
        WHERE room = ?
          AND epoch = ?
          AND token_id = ?
          AND limit_max = ?
          AND spent <= limit_max - ?
      `).run(
        lines, room, token.epoch,
        token.id, token.limit, lines
      );

      if (updated.changes !== 1) {
        this.db.exec("ROLLBACK");
        active = false;

        return {
          ok: false,
          status: 429,
          error: "v2 pass exhausted"
        };
      }

      const state = this.db.prepare(`
        SELECT spent, limit_max
        FROM v2_spends
        WHERE room = ? AND epoch = ? AND token_id = ?
      `).get(room, token.epoch, token.id);

      this.db.exec("COMMIT");
      active = false;

      return {
        ok: true,
        status: 200,
        remaining: state.limit_max - state.spent
      };
    } catch (error) {
      if (active && this.db.isTransaction) {
        this.db.exec("ROLLBACK");
      }
      throw error;
    }
  }
}
