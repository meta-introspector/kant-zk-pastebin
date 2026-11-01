//! Durable state: one postgres database, one append-only event table, one
//! projected task table.
//!
//! There is no postgres driver in this crate's dependency set, and adding one
//! would drag a TLS stack and a new vendored crate through the flake build for
//! a control plane that writes a handful of rows per task. So this module
//! drives `psql`, but not by pasting values into SQL: every value goes through
//! `-v name=value` and is used as `:'name'`, which is psql's own literal
//! quoting. A task title that reads `'); drop table fabric.events; --` is
//! stored as that string, and `injection_shaped_text_is_literal` proved it
//! against a real database before this comment existed.
//!
//! Events are inserted `on conflict (id) do nothing`, so replaying the same
//! event over a second transport (relay, Durable Object) is idempotent.

use std::io::Write;
use std::process::{Command, Stdio};

use serde_json::Value;

use crate::fabric::protocol::{self, Event, TaskRow};

const SCHEMA: &str = r#"
create schema if not exists fabric;
create table if not exists fabric.events (
  seq        bigserial primary key,
  id         text not null unique,
  kind       text not null,
  task       text,
  room       text,
  agent      text not null,
  ts         bigint not null,
  block_cid  text not null,
  body       jsonb not null,
  line       jsonb not null
);
create table if not exists fabric.tasks (
  id     text primary key,
  state  text not null,
  seq    bigint not null,
  body   jsonb not null
);
create index if not exists fabric_tasks_state on fabric.tasks (state);
create table if not exists fabric.meta (
  k text primary key,
  v text not null
);
"#;

pub struct Store {
    pub db: String,
    psql: String,
}

fn run(psql: &str, db: &str, script: &str, vars: &[(&str, &str)]) -> Result<String, String> {
    let mut cmd = Command::new(psql);
    cmd.args(["-X", "-q", "-v", "ON_ERROR_STOP=1", "-A", "-t", "-d", db]);
    for (k, v) in vars {
        cmd.arg("-v").arg(format!("{k}={v}"));
    }
    cmd.arg("-f").arg("-");
    cmd.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd.spawn().map_err(|e| format!("cannot run {psql}: {e}"))?;
    child
        .stdin
        .as_mut()
        .ok_or("no stdin")?
        .write_all(script.as_bytes())
        .map_err(|e| format!("cannot write to psql: {e}"))?;
    let out = child.wait_with_output().map_err(|e| format!("psql wait: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
}

impl Store {
    pub fn new(db: &str) -> Result<Store, String> {
        let psql = std::env::var("FABRIC_PSQL").unwrap_or_else(|_| "psql".to_string());
        let s = Store { db: db.to_string(), psql };
        s.exec(SCHEMA, &[])?;
        Ok(s)
    }

    fn exec(&self, script: &str, vars: &[(&str, &str)]) -> Result<String, String> {
        run(&self.psql, &self.db, script, vars)
    }

    /// Insert an event and, when it moved a task, its new projection. Returns
    /// the event's sequence number (existing one if this is a replay).
    pub fn append(&self, ev: &Event, task: Option<&TaskRow>) -> Result<i64, String> {
        let task_s = ev.task.clone().unwrap_or_default();
        let room_s = ev.room.clone().unwrap_or_default();
        let line = serde_json::to_string(&ev.line).map_err(|e| e.to_string())?;
        let body = serde_json::to_string(&ev.body).map_err(|e| e.to_string())?;
        let ts = ev.ts.to_string();
        let mut vars: Vec<(&str, &str)> = vec![
            ("id", &ev.id),
            ("kind", &ev.kind),
            ("task", &task_s),
            ("room", &room_s),
            ("agent", &ev.agent),
            ("ts", &ts),
            ("cid", &ev.block_cid),
            ("body", &body),
            ("line", &line),
        ];
        let task_json;
        if let Some(t) = task {
            task_json = serde_json::to_string(&t.value).map_err(|e| e.to_string())?;
            vars.push(("tid", &t.id));
            vars.push(("state", &t.state));
            vars.push(("taskbody", &task_json));
        }
        let script = if task.is_some() {
            r#"
begin;
insert into fabric.events (id, kind, task, room, agent, ts, block_cid, body, line)
  values (:'id', :'kind', nullif(:'task',''), nullif(:'room',''), :'agent',
          :'ts'::bigint, :'cid', :'body'::jsonb, :'line'::jsonb)
  on conflict (id) do nothing;
insert into fabric.tasks (id, state, seq, body)
  select :'tid', :'state', seq, :'taskbody'::jsonb from fabric.events where id = :'id'
  on conflict (id) do update set state = excluded.state, seq = excluded.seq, body = excluded.body;
select seq from fabric.events where id = :'id';
commit;
"#
        } else {
            r#"
begin;
insert into fabric.events (id, kind, task, room, agent, ts, block_cid, body, line)
  values (:'id', :'kind', nullif(:'task',''), nullif(:'room',''), :'agent',
          :'ts'::bigint, :'cid', :'body'::jsonb, :'line'::jsonb)
  on conflict (id) do nothing;
select seq from fabric.events where id = :'id';
commit;
"#
        };
        let out = self.exec(script, &vars)?;
        out.lines()
            .rev()
            .find_map(|l| l.trim().parse::<i64>().ok())
            .ok_or_else(|| format!("no seq returned by postgres: {out:?}"))
    }

    pub fn event_line(&self, id: &str) -> Result<Option<Value>, String> {
        let out = self.exec("select line::text from fabric.events where id = :'id';", &[("id", id)])?;
        if out.is_empty() {
            return Ok(None);
        }
        serde_json::from_str(&out).map(Some).map_err(|e| e.to_string())
    }

    pub fn events_since(&self, since: i64, limit: i64) -> Result<Vec<Value>, String> {
        let s = since.to_string();
        let l = limit.to_string();
        let out = self.exec(
            "select coalesce(json_agg(json_build_object('seq', seq, 'line', line) order by seq), '[]'::json)
             from (select seq, line from fabric.events where seq > :'since'::bigint order by seq limit :'limit'::bigint) t;",
            &[("since", &s), ("limit", &l)],
        )?;
        serde_json::from_str(&out).map_err(|e| e.to_string())
    }

    pub fn task(&self, id: &str) -> Result<Option<TaskRow>, String> {
        let out = self.exec("select body::text from fabric.tasks where id = :'id';", &[("id", id)])?;
        if out.is_empty() {
            return Ok(None);
        }
        let value: Value = serde_json::from_str(&out).map_err(|e| e.to_string())?;
        Ok(Some(row_from(value)))
    }

    pub fn tasks(&self, state: &str) -> Result<Vec<Value>, String> {
        let out = self.exec(
            "select coalesce(json_agg(body order by seq), '[]'::json) from fabric.tasks
             where (:'state' = '' or state = :'state');",
            &[("state", state)],
        )?;
        serde_json::from_str(&out).map_err(|e| e.to_string())
    }

    pub fn live_tasks(&self) -> Result<Vec<TaskRow>, String> {
        let out = self.exec(
            "select coalesce(json_agg(body), '[]'::json) from fabric.tasks
             where state in ('claimed','running');",
            &[],
        )?;
        let vs: Vec<Value> = serde_json::from_str(&out).map_err(|e| e.to_string())?;
        Ok(vs.into_iter().map(row_from).collect())
    }

    /// Chat lines for one task, oldest first.
    pub fn chat(&self, task: &str, since: i64) -> Result<Vec<Value>, String> {
        let s = since.to_string();
        let out = self.exec(
            "select coalesce(json_agg(json_build_object('seq', seq, 'line', line) order by seq), '[]'::json)
             from fabric.events where task = :'task' and kind = 'chat.say' and seq > :'since'::bigint;",
            &[("task", task), ("since", &s)],
        )?;
        serde_json::from_str(&out).map_err(|e| e.to_string())
    }

    /// Every agent that has ever sent an event, for `/peers`.
    pub fn agents(&self) -> Result<Vec<Value>, String> {
        let out = self.exec(
            "select coalesce(json_agg(a order by a), '[]'::json) from (select distinct agent as a from fabric.events) t;",
            &[],
        )?;
        serde_json::from_str(&out).map_err(|e| e.to_string())
    }

    pub fn max_seq(&self) -> Result<i64, String> {
        let out = self.exec("select coalesce(max(seq), 0) from fabric.events;", &[])?;
        out.trim().parse::<i64>().map_err(|e| e.to_string())
    }

    pub fn count(&self) -> Result<(i64, i64), String> {
        let out = self.exec(
            "select (select count(*) from fabric.events), (select count(*) from fabric.tasks);",
            &[],
        )?;
        let mut it = out.trim().split('|');
        let e = it.next().unwrap_or("0").parse().unwrap_or(0);
        let t = it.next().unwrap_or("0").parse().unwrap_or(0);
        Ok((e, t))
    }

    pub fn meta(&self, k: &str) -> Result<Option<String>, String> {
        let out = self.exec("select v from fabric.meta where k = :'k';", &[("k", k)])?;
        Ok(if out.is_empty() { None } else { Some(out) })
    }

    pub fn set_meta(&self, k: &str, v: &str) -> Result<(), String> {
        self.exec(
            "insert into fabric.meta (k, v) values (:'k', :'v')
             on conflict (k) do update set v = excluded.v;",
            &[("k", k), ("v", v)],
        )?;
        Ok(())
    }
}

fn row_from(value: Value) -> TaskRow {
    TaskRow {
        id: value["id"].as_str().unwrap_or_default().to_string(),
        state: value["state"].as_str().unwrap_or_default().to_string(),
        title: value["title"].as_str().unwrap_or_default().to_string(),
        kind: value["kind"].as_str().unwrap_or_default().to_string(),
        owner: value["owner"].as_str().map(|s| s.to_string()),
        lease_until: value["lease_until"].as_u64(),
        result_cid: value["result_cid"].as_str().map(|s| s.to_string()),
        value,
    }
}

/// Apply one verified event. The daemon funnels every ingress path — HTTP, the
/// unix socket, the relay, a Durable Object — through this function, so there
/// is exactly one place where a task can move.
pub fn ingest(
    store: &Store,
    ev: &Event,
    now: u64,
    lease_secs: u64,
) -> Result<Option<TaskRow>, String> {
    if ev.kind == "task.offer" {
        // A replayed offer is idempotent at the event table (same id), but it
        // must not overwrite a task that has already moved: an agent that
        // re-sends its offer cannot reset a worked task to `offered`.
        let would_be = format!("t{}", ev.id);
        if store.task(&would_be)?.is_some() {
            return Err(format!("task {would_be} already exists"));
        }
        let row = protocol::apply(None, ev, now, lease_secs)?;
        store.append(ev, Some(&row))?;
        return Ok(Some(row));
    }
    if ev.kind == "chat.say" || ev.kind == "peer.hello" {
        store.append(ev, None)?;
        return Ok(None);
    }
    let task_id = ev.task.clone().ok_or("event names no task")?;
    let current = store.task(&task_id)?;
    let row = protocol::apply(current.as_ref(), ev, now, lease_secs)?;
    store.append(ev, Some(&row))?;
    Ok(Some(row))
}

/// Re-offer tasks whose lease ran out. Returns how many moved.
pub fn sweep_leases(store: &Store, now: u64, lease_secs: u64) -> Result<usize, String> {
    let mut moved = 0;
    for row in store.live_tasks()? {
        if protocol::sweep(&row, now).is_some() {
            let ev = protocol::make_event(
                "task.expire",
                Some(&row.id),
                None,
                "fabric",
                now,
                serde_json::json!({"lease_until": row.lease_until}),
            );
            if ingest(store, &ev, now, lease_secs).is_ok() {
                moved += 1;
            }
        }
    }
    Ok(moved)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Tests share one database and each starts by dropping the schema, so
    /// they must not run concurrently. The lock is what makes `fresh()` mean
    /// fresh rather than "whatever another test just wrote".
    static DB_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn test_db() -> String {
        std::env::var("FABRIC_TEST_DB").unwrap_or_else(|_| "agent_fabric_test".to_string())
    }

    fn fresh() -> (std::sync::MutexGuard<'static, ()>, Store) {
        let guard = DB_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let db = test_db();
        // Recreate the schema, not the database: creating a database would need
        // a second connection and is outside what this test should assume.
        let s = Store::new(&db).unwrap();
        s.exec("drop schema if exists fabric cascade;", &[]).unwrap();
        (guard, Store::new(&db).unwrap())
    }

    #[test]
    fn event_round_trip_and_idempotent_replay() {
        let (_g, store) = fresh();
        let offer = protocol::make_event(
            "task.offer",
            None,
            None,
            "agent-a",
            100,
            json!({"title": "round trip", "kind": "general"}),
        );
        let row = ingest(&store, &offer, 100, 60).unwrap().unwrap();
        let seq1 = store.max_seq().unwrap();
        // Replaying the identical offer must not create a second task or row.
        assert!(ingest(&store, &offer, 100, 60).is_err());
        assert_eq!(store.max_seq().unwrap(), seq1);
        let (events, tasks) = store.count().unwrap();
        assert_eq!((events, tasks), (1, 1));
        assert_eq!(store.task(&row.id).unwrap().unwrap().state, "offered");
    }

    #[test]
    fn injection_shaped_text_is_literal() {
        let (_g, store) = fresh();
        let nasty = "'); drop table fabric.events; -- \\ \" \n second line";
        let offer = protocol::make_event(
            "task.offer",
            None,
            None,
            "agent-a",
            100,
            json!({"title": nasty}),
        );
        let row = ingest(&store, &offer, 100, 60).unwrap().unwrap();
        assert_eq!(row.title, nasty);
        // The table is still there and still holds the row.
        assert_eq!(store.count().unwrap(), (1, 1));
    }

    #[test]
    fn lease_sweep_reoffers_after_expiry() {
        let (_g, store) = fresh();
        let offer = protocol::make_event(
            "task.offer",
            None,
            None,
            "agent-a",
            100,
            json!({"title": "leased", "kind": "general"}),
        );
        let row = ingest(&store, &offer, 100, 60).unwrap().unwrap();
        let claim = protocol::make_event("task.claim", Some(&row.id), None, "agent-a", 100, json!({}));
        ingest(&store, &claim, 100, 60).unwrap();
        assert_eq!(sweep_leases(&store, 159, 60).unwrap(), 0);
        assert_eq!(sweep_leases(&store, 161, 60).unwrap(), 1);
        let back = store.task(&row.id).unwrap().unwrap();
        assert_eq!(back.state, "offered");
        assert_eq!(back.owner, None);
    }

    #[test]
    fn cursor_returns_each_event_once() {
        let (_g, store) = fresh();
        for i in 0..3u64 {
            let e = protocol::make_event(
                "chat.say",
                None,
                Some("room"),
                "agent-a",
                100 + i,
                json!({"text": format!("m{i}")}),
            );
            store.append(&e, None).unwrap();
        }
        let first = store.events_since(0, 10).unwrap();
        assert_eq!(first.len(), 3);
        let last_seq = first.last().unwrap()["seq"].as_i64().unwrap();
        assert!(store.events_since(last_seq, 10).unwrap().is_empty());
    }
}
