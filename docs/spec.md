# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

## 2. Design Contract (read first)

This block is defined by a fixed contract. Each driven output has a
declared **logic class**, a **source** (what its next value is computed
from), and a **latency** measured from the cycle an input is sampled.

| Output      | Logic class        | Next-state source                         | Latency from `rd` |
|-------------|--------------------|-------------------------------------------|-------------------|
| `res`       | registered (seq)   | rounded+saturated snapshot, loaded when `rd`=1 | 1 cycle       |
| `res_valid` | registered (seq)   | **the `rd` sampled this cycle** (one flip-flop) | 1 cycle       |
| `ovf`       | registered, sticky | saturation of the same readout            | aligned with `res_valid` |
| `acc`       | registered (seq)   | §4 table                                  | n/a               |

Contract rules (each is checkable):

- **R1** `res_valid` is exactly **one flip-flop after `rd`**. Its
  next-state equals the `rd` sampled on the current edge. There is **no
  intermediate `rd`-capture register** (`rd_q`, `rd_seen`, …) on this path.
- **R2** `res` loads the rounded/saturated snapshot on the same edge that
  sets `res_valid`; both appear at cycle *N+1* for an `rd` at *N*.
- **R3** `ovf` updates on the **same edge** as its `res_valid` (never one
  cycle later).
- **R4** All four `{clr, en}` combinations produce distinct `acc`
  next-states (§4).
- **R5** Snapshot is the **pre-update** accumulator value (§5).

## 3. Interface

| Port        | Dir | Type                  | Logic class | Latency        | Description                                  |
|-------------|-----|-----------------------|-------------|----------------|----------------------------------------------|
| `clk`       | in  | `logic`               | —           | —              | Clock; all sequential behavior on rising edge. |
| `rst`       | in  | `logic`               | —           | —              | Synchronous, active-high reset.              |
| `en`        | in  | `logic`               | —           | —              | Accumulate `a*b` this cycle.                 |
| `clr`       | in  | `logic`               | —           | —              | Clear the accumulator this cycle.            |
| `rd`        | in  | `logic`               | —           | —              | Request an accumulator readout this cycle.   |
| `a`         | in  | `logic signed [7:0]`  | —           | —              | Multiplicand.                                |
| `b`         | in  | `logic signed [7:0]`  | —           | —              | Multiplier.                                  |
| `res`       | out | `logic signed [15:0]` | registered  | `rd`+1         | Rounded + saturated readout result.          |
| `res_valid` | out | `logic`               | registered  | `rd`+1, 1-wide | One-cycle pulse, one flip-flop after `rd`.   |
| `ovf`       | out | `logic`               | registered  | with `res_valid` | Sticky saturation flag.                    |

Control inputs (`en`, `clr`, `rd`) are sampled every rising edge and may be
asserted in any combination. `a`/`b` are consumed only on cycles where the
accumulator takes a product (§4 table).

## 4. Accumulator

`acc` is a 28-bit signed two's-complement register. The product
`p = a * b` is a signed 16-bit value, sign-extended to 28 bits before use.

Next-state at each rising edge (`rst = 0`):

| `clr` | `en` | `acc` next value                                            |
|-------|------|-------------------------------------------------------------|
| 0     | 0    | `acc` (hold)                                                |
| 0     | 1    | `acc + p`                                                   |
| 1     | 0    | `0`                                                         |
| 1     | 1    | `p` (clear-then-accumulate: accumulator becomes the product alone) |

The grading testbench guarantees `acc` never exceeds signed 28-bit range;
wrap behavior is unspecified. Per **R4**, `clr=1,en=1` must not equal
`clr=1,en=0`.

## 5. Readout path

`rd` in cycle *t* requests a readout.

### 5.1 Snapshot (per R5)

The snapshot is `acc` as it stood at the **end of cycle *t−1***, i.e.
**before** any `en`/`clr` update in cycle *t*.

| Same-cycle input | Effect on this readout                                   |
|------------------|----------------------------------------------------------|
| `en=1` with `rd` | `acc` still updates normally; update is **not** in snapshot |
| `clr=1` with `rd`| readout returns the **pre-clear** value; clear applies after |

### 5.2 Rounding — round-half-to-even at the 8 LSBs

Let `q = floor(acc / 256)` and `r = snapshot − 256·q`, so `0 ≤ r ≤ 255`
(including for negative `acc` — arithmetic right shift already gives
`q = acc >>> 8`, `r = acc[7:0]`; do **not** apply a second negative
adjustment).

| Condition   | Rounded value |
|-------------|---------------|
| `r < 128`   | `q`           |
| `r > 128`   | `q + 1`       |
| `r == 128`  | `q` if `q` even, else `q + 1` |

The tie-break checks the parity of `q` (not the final result).

### 5.3 Saturation — after rounding

Clamp the **rounded** value to signed 16-bit `[−32768, +32767]`. Order
matters: rounding may itself exceed the range; saturation applies to the
rounded value.

### 5.4 Worked examples (`acc → res`) — full tie/saturation coverage

| `acc`     | `q`     | `r` | `res`  | class                                                    |
|-----------|---------|-----|--------|----------------------------------------------------------|
| 640       | 2       | 128 | 2      | +, tie, `q` even → stays                                 |
| 896       | 3       | 128 | 4      | +, tie, `q` odd → up                                     |
| −384      | −2      | 128 | −2     | −, tie, `q` even → stays                                 |
| −640      | −3      | 128 | −2     | −, tie, `q` odd → up (**not** −4)                        |
| 8388480   | 32767   | 128 | 32767  | +, tie, `q` odd → 32768 then saturates → overflow        |
| −8388608  | −32768  | 0   | −32768 | exact minimum — **not** an overflow, `ovf` unchanged     |

### 5.5 Readout timing (per R1/R2)

For an `rd` sampled at cycle *N*, `res_valid` and `res` appear at *N+1*
only — never *N+2*. `res_valid` is one flip-flop after `rd` (no extra
capture stage). Between readouts, `res` **holds**; it does not clear when
`res_valid` is low. Back-to-back `rd` cycles each take their own snapshot.

| cycle | `rd` | `res_valid` | `res`                      |
|-------|------|-------------|----------------------------|
| N     | 1    | 0           | previous held value        |
| N+1   | 0    | 1           | rounded/saturated snapshot |
| N+2   | 0    | 0           | holds value from N+1       |

## 6. Overflow flag

`ovf` is registered and sticky:

| Event                                   | `ovf` next value                         |
|-----------------------------------------|------------------------------------------|
| Readout saturates                       | 1 (set, same edge as its `res_valid` — R3) |
| Readout does not saturate               | unchanged                                |
| `clr` (or `rst`), no saturating readout | 0                                        |
| Saturating readout **and** `clr` same cycle | 1 (set wins)                         |

`res` always carries the clamped value; saturation is signaled only via
`ovf`.

## 7. Reset

`rst` is synchronous, active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` clear to 0.

## 8. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.

## 9. Verification checklist

- [ ] **Readout latency (R1/R2):** `rd` only at N ⇒ `res_valid`=1 at N+1
      and 0 at N+2; no intermediate `rd`-capture register.
- [ ] **`ovf` alignment (R3):** flag updates on the same edge as its
      `res_valid`.
- [ ] **`{clr,en}` (R4):** all four combinations distinct.
- [ ] **Snapshot (R5):** pre-update value; `en`/`clr` in the `rd` cycle
      excluded from the snapshot.
- [ ] **Rounding:** `r` = 127/128/129 for +/− and even/odd `q`; negative
      floor uses `acc>>>8` with no second adjustment.
- [ ] **Saturation:** rounded value exactly ±boundary vs one step beyond.
- [ ] **Sticky `ovf`:** holds across non-saturating readouts; cleared only
      by `clr`/`rst`; set wins on same-cycle `clr`.
