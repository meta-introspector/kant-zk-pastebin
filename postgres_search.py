#!/usr/bin/env python3
"""Fast postgres search service for kant-pastebin."""

import os
import json
import psycopg2
from psycopg2 import pool
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime


def json_default(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Object of type {obj.__class__.__name__} is not JSON serializable")


# Connection pool
pg_pool = psycopg2.pool.ThreadedConnectionPool(
    minconn=2,
    maxconn=10,
    host=os.getenv("PG_HOST", "localhost"),
    port=os.getenv("PG_PORT", "5432"),
    user=os.getenv("PG_USER", "mdupont"),
    dbname=os.getenv("PG_DB", "postgres"),
    password=os.getenv("PG_PASSWORD", "mdupont"),
)


def search_pastes(query: str, limit: int = 50):
    """Full-text search using tsvector."""
    if not query:
        return {"count": 0, "results": []}

    ts_query = " | ".join(query.split())

    conn = pg_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT p.id, p.title, p.description, p.ipfs_cid, p.cid_v0, p.cid_v1,
                   p.witness, p.timestamp, p.size, p.da51_addr,
                   p.orbifold_x, p.orbifold_y, p.orbifold_z,
                   ts_rank_cd(p.search_vector, to_tsquery(%s)) AS rank
            FROM pastes p
            WHERE p.search_vector @@ to_tsquery(%s)
            ORDER BY rank DESC, p.timestamp DESC
            LIMIT %s
        """,
            (ts_query, ts_query, limit),
        )

        results = []
        for row in cur.fetchall():
            results.append(
                {
                    "id": row[0] or "",
                    "title": row[1] or "",
                    "description": row[2] or "",
                    "ipfs_cid": row[3] or "",
                    "cid_v0": row[4] or "",
                    "cid_v1": row[5] or "",
                    "witness": row[6] or "",
                    "timestamp": row[7] or "",
                    "size": row[8] or 0,
                    "da51_addr": row[9] or "",
                    "orbifold": [row[10], row[11], row[12]] if row[10] else None,
                    "rank": float(row[13]) if row[13] else 0.0,
                }
            )
        return {"count": len(results), "query": query, "results": results}
    finally:
        pg_pool.putconn(conn)


def search_by_cid(cid: str):
    """Search by CID (cid_v0, cid_v1, ipfs_cid)."""
    conn = pg_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, title, description, cid_v0, cid_v1, witness, ipfs_cid,
                   timestamp, size, uucp_path
            FROM pastes
            WHERE cid_v0 = %s OR cid_v1 = %s OR ipfs_cid = %s
            LIMIT 1
        """,
            (cid, cid, cid),
        )

        row = cur.fetchone()
        if row:
            return {
                "id": row[0] or "",
                "title": row[1] or "",
                "description": row[2] or "",
                "cid_v0": row[3] or "",
                "cid_v1": row[4] or "",
                "witness": row[5] or "",
                "ipfs_cid": row[6] or "",
                "timestamp": row[7] or "",
                "size": row[8] or 0,
                "uucp_path": row[9] or "",
            }
        return None
    finally:
        pg_pool.putconn(conn)


def list_tags(limit: int = 50):
    """List all tags with counts."""
    conn = pg_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT tag, count(*) FROM paste_tags GROUP BY tag ORDER BY count DESC LIMIT %s",
            (limit,),
        )
        return [{"tag": r[0], "count": r[1]} for r in cur.fetchall()]
    finally:
        pg_pool.putconn(conn)


def ngram_search(query: str, n: int = 3, limit: int = 50):
    """Fast ngram-based search."""
    if len(query) < n:
        return {"count": 0, "results": []}

    # Generate ngrams from query
    words = query.lower().split()
    hashes = []
    for i in range(max(0, len(words) - n + 1)):
        ngram = " ".join(words[i : i + n])
        h = abs(hash(ngram)) % (2**31)
        hashes.append(h)

    if not hashes:
        return {"count": 0, "results": []}

    placeholders = ",".join(["%s"] * len(hashes))
    conn = pg_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute(
            f"""
            SELECT DISTINCT ON (p.id) p.id, p.title, p.description, p.ipfs_cid,
                   p.timestamp, p.size
            FROM pastes p
            JOIN ngram_index ni ON p.id = ni.paste_id
            WHERE ni.n = %s AND ni.hash IN ({placeholders})
            ORDER BY p.id, p.timestamp DESC
            LIMIT %s
        """,
            [n] + hashes + [limit],
        )

        results = []
        for row in cur.fetchall():
            results.append(
                {
                    "id": row[0] or "",
                    "title": row[1] or "",
                    "description": row[2] or "",
                    "ipfs_cid": row[3] or "",
                    "timestamp": row[4] or "",
                    "size": row[5] or 0,
                }
            )
        return {"count": len(results), "results": results}
    finally:
        pg_pool.putconn(conn)


class SearchHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)

        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
            return

        elif parsed.path == "/search":
            q = params.get("q", [""])[0]
            limit = int(params.get("limit", ["50"])[0])
            result = search_pastes(q, limit)

        elif parsed.path == "/cid":
            cid = params.get("cid", [""])[0]
            result = search_by_cid(cid) or {"found": False}

        elif parsed.path == "/tags":
            limit = int(params.get("limit", ["50"])[0])
            result = {"tags": list_tags(limit)}

        elif parsed.path == "/ngram":
            q = params.get("q", [""])[0]
            n = int(params.get("n", ["3"])[0])
            limit = int(params.get("limit", ["50"])[0])
            result = ngram_search(q, n, limit)

        else:
            self.send_response(404)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(result, default=json_default).encode())

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8086"))
    print(f"Starting postgres search service on port {port}")
    server = HTTPServer(("", port), SearchHandler)
    server.serve_forever()
