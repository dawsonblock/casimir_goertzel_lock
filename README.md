# Casimir Goertzel Lock-In Upgrade Package

This package upgrades the earlier one-vector Goertzel demo into a reusable FPGA lock-in IP starting point.

It is intended for the **measurement path**, not the physical actuation/memory-kernel path.

Correct architecture:

```text
Actuation path:
  FIR causal memory kernel -> DAC / actuator / boundary channel

Measurement path:
  ADC stream -> Goertzel/NCO lock-in -> I/Q -> CORDIC or CPU atan2 -> phase/magnitude/statistics
```

## Included

```text
rtl/goertzel_core.v          Overflow-safe Q17 Goertzel core
rtl/goertzel_axis_core.v     AXI-Stream style wrapper
rtl/correction_matrix_q30.v  2x2 phasor correction matrix

tools/goertzel_coeffgen.py   Coefficient generator
 tools/gen_goertzel_vectors.py Regression vector generator

tb/goertzel_tb.sv            Single-vector SystemVerilog testbench
run_one_vector.sh            Run one vector with iverilog if available
run_regression.sh            Run all generated vectors with iverilog if available
coeffs/                      Generated coefficient metadata
vectors/                     Generated regression vectors
```

## Quick start

From the package root:

```bash
python tools/goertzel_coeffgen.py --fs 10000000 --freq 2300000 --n-block 1000 --q-shift 17 --out-dir coeffs --name science_2p3MHz
python tools/goertzel_coeffgen.py --fs 10000000 --freq 2400000 --n-block 1000 --q-shift 17 --out-dir coeffs --name pilot_2p4MHz
python tools/gen_goertzel_vectors.py --out-dir vectors --fs 10000000 --freq 2300000 --n-block 1000 --q-shift 17
./run_one_vector.sh vectors/tone_phase_00
./run_regression.sh
```

If `iverilog` is unavailable, use Vivado, Questa, Xcelium, Verilator, or another SystemVerilog simulator with:

```text
rtl/goertzel_core.v
tb/goertzel_tb.sv
+VECTOR_DIR=vectors/tone_phase_00
```

## Signal conventions

For coherent block extraction:

```text
s[n] = x[n] + 2*cos(w)*s[n-1] - s[n-2]
I    = s[N] - s[N-1]*cos(w)
Q    = s[N-1]*sin(w)
```

For a coherent tone, the estimated amplitude is approximately:

```text
A = 2 * sqrt(I^2 + Q^2) / N_BLOCK
```

The sign of `Q` depends on the chosen DFT/lock-in convention. Verify sign using injected known phase offsets before using it for phase correction.

## Safety and overflow policy

`goertzel_core.v` computes recurrence/feedforward intermediates in wide paths, checks whether values fit in signed 48-bit state/output space, and rejects overflowed outputs:

```text
block_done      pulses for every completed block
overflow_block  pulses if that block overflowed
dout_valid      pulses only when block completed without overflow
overflow_sticky remains high until clear_overflow
```

Downstream logic should ignore `i_out/q_out` unless `dout_valid == 1`.

## Production gaps remaining

This is an upgraded IP starting point, not final silicon-grade RTL. Remaining work:

- AXI-Lite coefficient/status register bank
- CORDIC or CPU-side atan2 integration
- reset/gap/back-to-back stress testbench
- formal properties
- timing constraints and synthesis reports for target FPGA
- hardware-in-the-loop test using real ADC/DAC clock domains

