# Verification Plan

## Already included

- Coherent tone with 8 phase cases
- Amplitude sweep
- DC offset sweep
- Noise sweep
- Off-bin tone
- Two-tone interference
- Negative-only vector
- Near-full-scale vector
- Full-scale positive/negative vectors
- Deliberate overflow injection (alternating polarity, adversarial amplitude)
- Sign-convention validation vectors (known phase offsets)

## Already implemented testbenches

- `tb/goertzel_tb.sv` - Single-vector golden model comparison
- `tb/goertzel_axis_tb.sv` - AXI-Stream wrapper with stall/backpressure
- `tb/reset_gap_tb.sv` - Reset recovery, din_valid gaps, back-to-back blocks
- `tb/goertzel_formal_assertions.sv` - Timing-agnostic formal checks (count range, valid/overflow exclusivity, counter monotone, sticky overflow, reset recovery)

## Next stress tests to implement

Replaced with the above concrete testbenches and vectors. Remaining high-value additions:

1. Randomized coefficient sets from `goertzel_coeffgen.py` sweep
2. Two-channel simultaneous validation (science + pilot)
3. Correction-matrix check against known-rotation vectors
4. Pitfall test: feeddin_valid=false with timing guarantees violated on purpose

## Pass criteria

For non-overflow vectors:

```text
dout_valid == 1
overflow_block == 0
i_out == expected_i
q_out == expected_q
```

For overflow vectors:

```text
block_done == 1
overflow_block == 1
dout_valid == 0
```
