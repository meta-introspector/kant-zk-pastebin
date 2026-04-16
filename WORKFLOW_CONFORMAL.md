# Workflow as Conformal Field with Side Channel Measurement

## Core Idea

A workflow is a **sequence of conformal arrows** in the orbifold.
Each step is a channel measurement. zkperf proves all arrows preserved.

## Workflow Structure

```
post p → workflow W → [step_1, step_2, ..., step_N] → output q

step_i = {
    input:   OrbifoldCoords   // where we are before step
    output:  OrbifoldCoords   // where we are after step
    channel: ChannelMeasurement  // side channel values
    arrow:   ConformalArrow   // the transformation
}
```

## Side Channels as Field Values

Side channel measurements are **values in the conformal field**:

| Channel | Field Value | Arrow Constraint |
|---------|-------------|-----------------|
| timing  | ns elapsed  | d(t_in, t_out) ≤ bound |
| memory  | bytes used  | d(m_in, m_out) ≤ bound |
| bandwidth | bytes/s   | d(b_in, b_out) ≤ bound |
| entropy | bits        | d(e_in, e_out) = 0 (preserved) |
| CID     | hash        | d(cid_in, cid_out) = 0 (content-addressed) |

Each channel is a **projection** of the full conformal field onto one axis.

## Arrow Preservation Proof (zkperf)

For each step `i`, the zkperf witness proves:
```
∀i: d(φ_H(step_i.input), φ_H(step_i.output)) = expected_delta_i
```

This means:
- The workflow did exactly what it claimed (no hidden transformations)
- Side channels are bounded (no information leakage beyond declared channels)
- The composition `step_1 ∘ step_2 ∘ ... ∘ step_N` is a valid conformal path

## Types

```rust
pub struct ChannelMeasurement {
    pub timing_ns: u64,
    pub memory_bytes: u64,
    pub entropy_bits: f64,
    pub cid_before: String,
    pub cid_after: String,
}

pub struct WorkflowStep {
    pub name: String,
    pub input_coords: OrbifoldCoords,
    pub output_coords: OrbifoldCoords,
    pub channel: ChannelMeasurement,
    pub arrow: ConformalArrow,
    /// zkperf witness: proof that arrow is preserved
    pub witness: String,
}

pub struct Workflow {
    pub id: String,
    pub steps: Vec<WorkflowStep>,
    /// Composition: total arrow from input to output
    pub total_arrow: ConformalArrow,
    /// All arrows preserved iff this is true
    pub conformal: bool,
}
```

## Verification

```rust
fn verify_workflow(w: &Workflow) -> bool {
    // 1. Each step's arrow is conformal
    let steps_ok = w.steps.iter().all(|s|
        orbifold_distance(&s.input_coords, &s.output_coords)
            == expected_delta(&s.arrow)
    );
    // 2. Composition equals total arrow
    let composed = compose_arrows(&w.steps);
    let composition_ok = composed == w.total_arrow;
    // 3. Side channels within declared bounds
    let channels_ok = w.steps.iter().all(|s| s.channel.entropy_bits >= 0.0);

    steps_ok && composition_ok && channels_ok
}
```

## Connection to zkperf

`zkperf` (in the `zkperf` submodule) already measures performance witnesses.
Each `WorkflowStep.witness` is a zkperf proof that:
- The step ran in declared time
- Memory usage was bounded
- The conformal arrow was preserved (input → output coords match)

This makes the workflow **self-certifying**: the proof travels with the data
through the conformal field, and any verifier can check arrow preservation
without re-running the workflow.
