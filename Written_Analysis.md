# Written Analysis

20 Rollout Trace: https://www.hud.ai/jobs/5b12be34-8916-4930-b7ae-be3342506f91/traces  
Trace after modifying spec: https://www.hud.ai/jobs/84f9661cd7bf45c6b14977877bdac871/traces (%70 Pass Rate)

## A. Root Cause Analysis

### What went wrong
**Readout Latency Bug.[Task 5c8deeb], [Task 6884079b], [Task 2aaf2962], [Task 04ef0f53], [Task 842aefd2], [Task 5f436941], [Task fec74f51], [Task dcd3d237], [Task 4c78fe78], [Task 3fa0f847]**  
The RTL adds one extra clock cycle of delay before `res_valid` and `res` become valid. Instead of connecting `res_valid` straight to `rd`, the design first copies `rd` into a new signal, `rd_reg` (`rd_reg <= rd`), and then sets `res_valid` from `rd_reg` (`res_valid <= rd_reg`).

Tracing it cycle by cycle: `rd` is high at cycle T. On the clock edge closing cycle T, `rd_reg` is loaded with `rd`, so `rd_reg` becomes 1 only at cycle T+1. Then `res_valid <= rd_reg` is a second register write — it samples `rd_reg` and only updates `res_valid` on the *next* edge, at cycle T+2. So instead of `res_valid` rising at T+1 as the spec requires, it rises at T+2. Every readout is delayed by one extra cycle.

**Why it went wrong:** The agent claims the staging register still produce one-cycle latency, missing that `res_valid <= rd_reg` is itself a register write that only takes effect one cycle after `rd_reg` updates. It added the extra register out of a common "stage your inputs for safety" instinct without verifying cycle counts. 

## B. Faulty Assumptions / Missed Insights

Everything else in the design was done correctly: the accumulator logic for all four `{clr, en}` cases, the rounding, and the saturation all matched the spec. The only mistake was in the timing of the readout path.It added an extra pipeline register for `rd`, causing the readout path to have two cycles of latency instead of the required one. The agent registered the inputs and it causes latency. The agent assumed that adding an extra pipeline stage in the readout path would not change the required behavior.

What actually happened is that the agent lost track of timing: it assumed `rd_reg` already matched `rd` within the same cycle, but a register only picks up the new value on the next clock edge, not immediately. Because of that wrong assumption, stacking a second register didn't look risky — but each register adds its own cycle of delay. This kind of mistake is common in synchronous design: confusing a signal's current value with the value it will hold after the next edge. Tracing the design cycle by cycle, rather than just describing what it was supposed to do, would have surfaced this immediately.

## C. Prompt Modifications

I have modified only `docs/spec.md` file without changing the prompt. I reviewed the FM-1–FM-11 failure-mode tags in the provided cocotb testbench and examined all failed tasks. I also compared them against my own golden RTL model and made the following adjustments to the specification.

1. **Clarified that clr and en are independent control signals, and all four {clr, en} combinations must produce distinct accumulator updates.**
2. **Clarified that the round-half-to-even tie-break must check the parity of q itself, before any increment is applied.**
3. **Appended two boundary examples** derived from `snapshot = 256·q + r`, covering even/odd tie cases, a tie that rounds into overflow and saturates, and the exact minimum value that does not set ovf.
4. **Appended a fifth worked example, a negative-accumulator tie case showing how rounding works when q is odd, regardless of sign.**
5. **Specified that the readout path must have exactly one clock cycle of latency from sampling rd to asserting res_valid and presenting res.**


[Task 5c8deeb]: https://www.hud.ai/trace/5cb8deeb-747b-45f9-81e7-7ba24fd8c8f6 "20 Rollout Trace Task Details"
[Task 6884079b]: https://www.hud.ai/trace/6884079b-1f33-4cd8-b83c-1236b5433933 "20 Rollout Trace Task Details"
[Task 2aaf2962]: https://www.hud.ai/trace/2aaf2962-0215-45e9-9414-53710cf98598 "20 Rollout Trace Task Details"
[Task 04ef0f53]: https://www.hud.ai/trace/04ef0f53-56e0-4c47-98d7-10201d104d28 "20 Rollout Trace Task Details"
[Task 842aefd2]: https://www.hud.ai/trace/842aefd2-91b4-4618-b993-40c134d76aa8 "20 Rollout Trace Task Details"
[Task 5f436941]: https://www.hud.ai/trace/5f436941-1902-4c2f-948d-009678d68458 "20 Rollout Trace Task Details"
[Task fec74f51]: https://www.hud.ai/trace/fec74f51-160a-4710-ab54-d9420d4caec1 "20 Rollout Trace Task Details"
[Task dcd3d237]: https://www.hud.ai/trace/dcd3d237-7a2a-4bcd-898f-3c2b95e27ea7 "20 Rollout Trace Task Details"
[Task 4c78fe78]: https://www.hud.ai/trace/4c78fe78-f348-44a5-a00f-79164de69fb3 "20 Rollout Trace Task Details"
[Task 3fa0f847]: https://www.hud.ai/trace/3fa0f847-5a11-4b5b-816e-0c2a29c360f9 "20 Rollout Trace Task Details"
