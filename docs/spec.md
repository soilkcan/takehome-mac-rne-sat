# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

## 2. Interface

| Port        | Dir | Type              | Description                                      |
|-------------|-----|-------------------|--------------------------------------------------|
| `clk`       | in  | `logic`           | Clock. All sequential behavior on the rising edge. |
| `rst`       | in  | `logic`           | Synchronous, active-high reset.                  |
| `en`        | in  | `logic`           | Accumulate `a*b` this cycle.                     |
| `clr`       | in  | `logic`           | Clear the accumulator this cycle.                |
| `rd`        | in  | `logic`           | Request a readout accumulator value this cycle.           |
| `a`         | in  | `logic signed [7:0]`  | Multiplicand.                                |
| `b`         | in  | `logic signed [7:0]`  | Multiplier.                                  |
| `res`       | out | `logic signed [15:0]` | Rounded + saturated readout result (registered). |
| `res_valid` | out | `logic`           | One-cycle pulse, exactly one cycle after each `rd`. |
| `ovf`       | out | `logic`           | Sticky saturation flag (registered).             |

All control inputs (`en`, `clr`, `rd`) are sampled on every rising edge and
may be asserted in any combination. `a` and `b` are consumed only on cycles
where the accumulator takes a product (see §3).

## 3. Accumulator

The internal accumulator `acc` is a 28-bit signed two's-complement register.
The product `p = a * b` is a signed 16-bit value, sign-extended to 28 bits
before use.

Accumulator update at each rising edge (with `rst = 0`):

| `clr` | `en` | `acc` next value |
|-------|------|------------------|
| 0     | 0    | `acc` (hold)     |
| 0     | 1    | `acc + p`        |
| 1     | 0    | `0`              |
| 1     | 1    | `p` — clear-then-accumulate: the accumulator becomes the new product alone |

The grading testbench guarantees the accumulator value never exceeds the
signed 28-bit range, so accumulator wrap behavior is unspecified and need
not be handled.

`clr` and `en` are independent bits — all four combinations of
`{clr, en}` must produce distinct `acc` next-state behavior, exactly as
given in the table above. In particular, `clr=1, en=1` must not be
treated the same as `clr=1, en=0`.

## 4. Readout path

Asserting `rd` in cycle *t* requests a accumulator value readout.

**Snapshot value.** The snapshot is the accumulator value as it stood at
the end of cycle *t−1* — that is, **before** any accumulator update
(`en`/`clr`) occurring in cycle *t*. An `en` asserted in the same cycle as
`rd` still updates the accumulator normally; it is simply not part of that
snapshot. A `clr` asserted in the same cycle as `rd` clears the accumulator
**after** the accumulator value is taken (the readout returns the pre-clear value).

**Rounding — round-half-to-even at the 8 LSBs.** Let
`q = floor(accumulator value / 256)` and `r =  snapshot − 256·q`, so that
`0 ≤ r ≤ 255` — including for negative accumulator values. The rounded value is:

- `q` if `r < 128`;
- `q + 1` if `r > 128`;
- on a tie (`r == 128`): `q` if `q` is even, else `q + 1`.

Note that the tie-break checks the parity of `q` itself, not the parity of
the final rounded result — since `q` and `q+1` always have opposite parity,
checking `q`'s low bit is sufficient.

**Saturation — applied after rounding.** The rounded value is then clamped
to the signed 16-bit range `[−32768, +32767]`. Note the order: rounding is
performed first and may itself carry the value out of the 16-bit range;
saturation applies to the **rounded** value.

**Registration and hold.** `res` and `res_valid` are registered outputs. In
cycle *t+1*, `res_valid` is 1 and `res` carries the rounded, saturated
accumulator value. `res_valid` is exactly one cycle wide per `rd`. Between readouts,
`res` **holds** its last value; it does not clear when `res_valid` is low.
Back-to-back `rd` cycles are permitted and each takes its own accumulator value.

Worked examples (`accumulator value → res`):


| accumulator value   | q      | r   | res              | note                                          |
|------------|--------|-----|------------------|-------------------------------------------------|
| 640        | 2      | 128 | 2                | tie, q even → stays                            |
| 896        | 3      | 128 | 4                | tie, q odd → rounds up                         |
| −384       | −2     | 128 | −2               | tie, q even → stays                            |
| 8388480    | 32767  | 128 | 32767            | tie, q odd → rounds up to 32768, then saturates to 32767 — this is an overflow|
| −8388608   | −32768 | 0   | −32768           | exactly the minimum representable value — this is NOT an overflow, `ovf` stays unchanged |

**One-cycle readout latency (critical).** Sampling `rd` at cycle *N*
must produce `res_valid = 1` (and the matching `res`) at cycle *N+1*
only. Latency of *N+2* or more is incorrect.

Correct shape: capture the snapshot / round / saturate into the
`res` register, and set `res_valid` from the *same* sampled `rd` in
that same edge — i.e. `res_valid` next-state is the `rd` sampled this
cycle (one register stage after `rd`).

Incorrect shape (common mistake): registering `rd` into an
intermediate flag (`rd_q`, `rd_seen`, `snapshot_valid`, …) and then
registering `res_valid` from that flag. That is two flip-flop stages
and yields `res_valid` at *N+2*. Do not do this.

Cycle timing:

| cycle | `rd` | `res_valid` | `res`                          |
|-------|------|-------------|--------------------------------|
| N     | 1    | 0           | previous held value            |
| N+1   | 0    | 1           | rounded/saturated snapshot     |
| N+2   | 0    | 0           | holds value from N+1           |

## 5. Overflow flag

`ovf` is a registered, sticky flag:

- **Set** whenever a readout saturates (the rounded accumulator value fell outside
  `[−32768, 32767]`). The flag update lands in the same cycle as the
  corresponding `res_valid`.
- **Cleared** only by `clr` (or `rst`).
- **Same-cycle priority:** if a saturating readout coincides with `clr` in
  the same cycle, the set wins — `ovf` is 1 in the following cycle. `clr`
  clears the flag only when no saturating readout lands that same cycle.
- A readout that does not saturate leaves `ovf` unchanged. `res` always
  carries the clamped value; saturation is signaled only via `ovf`.

## 6. Reset

`rst` is synchronous and active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` all clear
to 0.

## 7. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.

## 8. Verification checklist

Before considering the implementation complete, verify each of the
following scenarios against the rules above:

- [ ] **Reset:** `rst` asserted clears `acc`, `res`, `res_valid`, and `ovf`
      to 0, regardless of other inputs.
- [ ] **Accumulate:** `en=1`, `clr=0` adds the signed product `a*b` into
      `acc` on the next edge.
- [ ] **Clear:** `clr=1`, `en=0` zeroes `acc` on the next edge.
- [ ] **Clear + enable together:** `clr=1`, `en=1` sets `acc` to the new
      product alone (not the product added to zero-then-something-else —
      just the plain product).
- [ ] **Readout with concurrent update:** `rd=1` together with `en=1` (or
      `clr=1`) in the same cycle — snapshot must reflect the accumulator
      value *before* that cycle's update, per §4.1.
- [ ] **Back-to-back readouts:** two or more consecutive `rd=1` cycles each
      produce their own correctly-timed one-cycle `res_valid` pulse and
      correct snapshot.
- [ ] **Maximum positive accumulator values:** snapshot values near
      `+32767 * 256` and above, to exercise rounding and saturation at the
      positive boundary.
- [ ] **Maximum negative accumulator values:** snapshot values near
      `−32768 * 256` and below, to exercise rounding and saturation at the
      negative boundary.
- [ ] **Rounding boundaries:** remainders of exactly 127, 128, and 129
      (i.e. just below, exactly at, and just above the tie point), for both
      positive and negative snapshots, and for both even and odd `q`.
- [ ] **Saturation boundaries:** rounded values exactly at `+32767`/`−32768`
      (no saturation, flag unchanged) versus one step beyond (`+32768`/
      `−32769`, saturation triggers, flag sets).
- [ ] **Overflow sticky behavior:** `ovf` remains set across later
      non-saturating readouts and non-`clr` cycles, is cleared only by
      `clr` (or `rst`), and — when a saturating readout coincides with
      `clr` — remains set (saturation priority), per §5.1.
- [ ] **Readout latency:** with `rd=1` only in cycle N, `res_valid`
      is 1 in cycle N+1 and 0 in cycle N+2 (not delayed by an extra
      pipeline stage).