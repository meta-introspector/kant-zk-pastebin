---
name: do-scheduler-modes
priority: HIGH
depends_on: federated-p2p-relay
---

# do-scheduler-modes

**Status:** planning · **Date:** 2026-10-03

## Goal

Enhance the federated P2P relay with a scheduler that manages three distinct Durable Object usage modes to optimize resource utilization, crash recovery, and scalability under the Cloudflare Free-plan constraints.

## Instructions

- Implement a scheduler that transitions Durable Objects between modes based on workload and user activity
- Sleeping mode: minimal resource consumption, wakes on user requests
- Awake mode: active state synchronization with peer Durable Objects for crash recovery
- Overage mode: load shedding via work distribution and account provisioning
- Maintain compatibility with existing federated P2P relay specification
- All modes must respect Free-plan budget limits

## Discoveries

- Current federated-p2p-relay spec (v0.1) uses standard Durable Object patterns with:
  - GatewayDO for WSS peer connections
  - MailboxDO for per-recipient message queuing
  - TopicDO for ordered event delivery
  - FederationDO for namespace mapping between networks
- Free-plan limits: ~100k Worker requests, 100k DO requests, 10ms CPU/invocation/day/account
- Existing implementation lacks dynamic resource adaptation
- Crash recovery currently relies solely on DO persistence
- No mechanism for horizontal scaling under load

## Accomplished

- [ ] Federated P2P relay specification documented (v0.1)
- [ ] Core Durable Object topology defined (GatewayDO, MailboxDO, TopicDO, FederationDO)
- [ ] Frame protocol and federation mechanisms specified
- [ ] Free-plan budget constraints analyzed
- [ ] Five-phase implementation roadmap established

## Not Done / In Progress

- [ ] Design scheduler algorithm for mode transitions
- [ ] Implement Sleeping mode (hibernation-aware, request-triggered wake)
- [ ] Implement Awake mode (peer state synchronization, crash recovery protocol)
- [ ] Implement Overage mode (work distribution, account provisioning triggers)
- [ ] Define mode transition metrics and thresholds
- [ ] Integrate scheduler with federated-p2p-relay implementation
- [ ] Validate mode behavior against Free-plan limits

## Relevant Files

| File | Status | Notes |
|------|--------|-------|
| `tasks/federated-p2p-relay/SYSTEM.md` | done | Base federated relay specification |
| `server/worker.js` | reference | Current Room DO implementation |
| `server/wrangler.toml` | reference | DO bindings and asset configuration |
| `web/p2p.html` | reference | Existing P2P web interface |
| `web/kant-p2p.mjs` | reference | P2P application logic |
| `web/kant-libp2p.mjs` | reference | libp2p file transport |
| `server/relay.mjs` | reference | Node.js twin implementation |

## Next Actions

1. **Define scheduler metrics**: Request rate, latency, memory usage, DO request count, CPU time
2. **Design Sleeping mode**: Hibernation API utilization, wake-on-request patterns, minimal state retention
3. **Design Awake mode**: Peer discovery protocol, state exchange format, conflict resolution for crash recovery
4. **Design Overage mode**: Load shedding algorithms, user redirection mechanics, account provisioning triggers
5. **Create mode transition rules**: Thresholds and hysteresis to prevent thrashing
6. **Update federated-p2p-relay spec**: Add scheduler and mode requirements to v0.2
7. **Prototype mode implementation**: Start with Sleeping → Awake transitions in GatewayDO
8. **Validate against Free-plan**: Simulate mode behavior within budget constraints
9. **Document mode interactions**: How modes affect frame protocol, federation, and persistence
10. **Add observability**: Metrics for mode distribution, transition frequency, and resource savings

## Mode Specifications

### 1. Sleeping Mode
- **Trigger**: Low/zero request rate for configurable period
- **Behavior**: 
  - Utilizes Durable Object WebSocket Hibernation API
  - Retains only essential state in SQLite (minimal footprint)
  - Releases WebSocket connections and in-memory caches
  - Wakes automatically on incoming requests
- **Recovery**: State restored from SQLite on wake
- **Cost**: Near-zero during sleep, normal on wake

### 2. Awake Mode
- **Trigger**: Sustained user activity above threshold
- **Behavior**:
  - Maintains active WebSocket connections
  - Participates in peer state synchronization protocol
  - Exchanges recovery state with online peers
  - Can reconstruct state from peers after crash (reducing DO reliance)
  - Continues normal message routing and processing
- **Recovery**: Peer-assisted state reconstruction + SQLite checkpoint
- **Cost**: Normal DO usage plus network overhead for sync

### 3. Overage Mode
- **Trigger**: Resource utilization approaching Free-plan limits
- **Behavior**:
  - Implements load shedding algorithms
  - Redirects new users to less-loaded peers or federated networks
  - Signals need for additional accounts via control plane
  - May temporarily reduce functionality to stay within budget
  - Work distribution via federated namespace routing
- **Recovery**: Returns to Awake/Sleeping when load decreases
- **Cost**: Optimized to remain within Free-plan bounds

## Scheduler Responsibilities

- Monitor system metrics (request rate, latency, DO usage, CPU)
- Evaluate transition conditions with hysteresis
- Initiate mode changes gracefully (no dropped connections)
- Coordinate mode transitions across federated networks
- Report mode distribution and resource usage for observability
- Respect network-specific configurations and policies

## Integration Points

- **GatewayDO**: Primary mode controller (handles user connections)
- **MailboxDO**: Inherits scheduler state for queue management
- **TopicDO**: Adjusts fan-out and persistence based on mode
- **FederationDO**: Coordinates mode-aware namespace handling
- **Control Plane**: Account provisioning signals for Overage mode

## Validation Approach

1. Unit tests for mode transition logic
2. Integration tests simulating user load patterns
3. Chaos testing for crash recovery in Awake mode
4. Load testing to verify Overage mode effectiveness
5. Budget simulation to ensure Free-plan compliance
6. Canary deployment with metrics collection

## Open Questions

- What metrics best indicate need for each mode?
- How fast should mode transitions occur?
- What state is exchanged in Awake mode synchronization?
- How does Overage mode interact with federation policies?
- Should mode state be persisted or ephemeral?
- How do we handle mixed-mode federated networks?
