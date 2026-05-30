# Casimir Goertzel Lock-In Upgrade

A reusable FPGA measurement-path IP for coherent single-frequency I/Q extraction using Q17 fixed-point Goertzel algorithm, with comprehensive verification, AXI-Stream integration, and phase-correction capabilities.

![GitHub last commit](https://img.shields.io/github/last-commit/dawsonblock/casimir_goertzel_lockin_upgrade)
![GitHub repo size](https://img.shields.io/github/repo-size/dawsonblock/casimir_goertzel_lockin_upgrade)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Overview

This package implements a deterministic fixed-point measurement subsystem for extracting coherent frequency bins from sampled data. It extracts I/Q phasors using a Goertzel recurrence and provides infrastructure for active pilot-tone phase tracking in dynamic measurement systems (e.g., Casimir effect, chiral boundary experiments).

**Key Innovation**: Strict separation of measurement path (Goertzel-based I/Q extraction) from actuation path (FIR causal memory kernel), enabling clean phase-tracking architectures without conflating measurement and control concerns.

## Features

- **Overflow-Safe Goertzel Core** (`goertzel_core.v`)
  - Q17 fixed-point coefficients with 48-bit internal state
  - Wide intermediate paths for overflow detection before truncation
  - `block_done`, `dout_valid`, `overflow_block`, `overflow_sticky` status signals
  - Deterministic block latency with sample-accurate timing

- **AXI-Stream Wrapper** (`goertzel_axis_core.v`)
  - Backpressure-aware input/output handshaking
  - Holds output phasor until consumed to prevent block-boundary ambiguity
  - Outputs coefficient ID and block index for traceability

- **Phasor Correction Matrix** (`correction_matrix_q30.v`)
  - 2x2 Q30 fixed-point matrix for rotation/calibration
  - Designed for pilot-tone-based phase drift correction

- **AXI-Lite Register Bank** (`goertzel_regbank.v`)
  - Runtime coefficient reprogramming
  - Status/control registers (block counter, overflow flags, clear)
  - Coefficient ID readback

- **Top-Level Integration** (`goertzel_top.v`)
  - Dual-channel architecture (science + pilot Goertzel cores)
  - Shared ADC demux with priority arbitration
  - Correction matrix integration point

- **Comprehensive Verification**
  - Python-generated golden vectors with exact fixed-point expectations
  - 31 regression vectors covering amplitude, phase, DC offset, noise, two-tone, off-bin, overflow, and sign-convention cases
  - Stress testbenches for reset recovery, `din_valid` gaps, back-to-back blocks
  - AXI wrapper testbench with stall/backpressure scenarios
  - SystemVerilog formal assertions for safety properties

## Architecture

```
                                  +---------------------+
                                  | ARM / Control Plane |
                                  | atan2, calibration  |
                                  | coeff IDs, logging  |
                                  +----------+----------+
                                              |
                                              v
           +------------------+        +------------------+        +---------------------+
 ADC ---> | Science Goertzel   | -----> | Correction       | ---> | DMA / Statistics    |
   \----> | (2.3 MHz, k=230)   |        | Matrix (Q30)     |        +------------------+
           +------------------+        +------------------+
                                              ^
           +------------------+        +------------------+
            \-> | Pilot Goertzel   | ---> | Phase Drift    |
                | (2.4 MHz, k=240)   |    | Estimator      |
                 +------------------+        +------------------+

Actuation Path (Separate Concern):
  FIR Causal Memory Kernel -> DAC -> Actuator / Boundary Channel
```

## Quick Start

### Prerequisites
- Python 3.7+ with NumPy
- Icarus Verilog (`iverilog`) or compatible SystemVerilog simulator (Vivado, Questa, Verilator)
- GNU Make (optional)

### Generate Coefficients and Vectors
```bash
# Science channel (2.3 MHz)
python tools/goertzel_coeffgen.py \
  --fs 10000000 \
  --freq 2300000 \
  --n-block 1000 \
  --q-shift 17 \
  --out-dir coeffs \
  --name science_2p3MHz

# Pilot channel (2.4 MHz)
python tools/goertzel_coeffgen.py \
  --fs 10000000 \
  --freq 2400000 \
  --n-block 1000 \
  --q-shift 17 \
  --out-dir coeffs \
  --name pilot_2p4MHz

# Generate regression vectors
python tools/gen_goertzel_vectors.py \
  --out-dir vectors \
  --fs 10000000 \
  --freq 2300000 \
  --n-block 1000 \
  --q-shift 17
```

### Run Verification
```bash
# Single vector test (IVC)
./run_one_vector.sh vectors/tone_phase_00

# Full regression suite
./run_regression.sh
```

### Simulation with Custom Vectors
```bash
# Using Icarus Verilog
iverilog -g2012 -o sim/goertzel_tb.vvp \
  rtl/goertzel_core.v tb/goertzel_tb.sv
vvp sim/goertzel_tb.vvp +VECTOR_DIR=vectors/tone_phase_00

# Using Verilator (example)
verilator --cc --exe -I rtl -I tb \
  rtl/goertzel_core.v tb/goertzel_tb.sv \
  --top-module goertzel_tb --build
./obj_dir/Vgoertzel_tb +VECTOR_DIR=vectors/tone_phase_00
```

## File Structure

```
.
├── rtl/                     # Register-transfer level source
│   ├── goertzel_core.v      # Q17 fixed-point Goertzel extractor
│   ├── goertzel_axis_core.v # AXI-Stream wrapper
│   ├── correction_matrix_q30.v # Phasor rotation matrix
│   ├── goertzel_regbank.v   # AXI-Lite register bank
│   ├── goertzel_top.v       # Dual-channel top-level
│   └── goertzel_formal_assertions.sv # Formal properties
├── tb/                      # Testbenches
│   ├── goertzel_tb.sv       # Golden-model comparison
│   ├── goertzel_axis_tb.sv  # AXI wrapper stress tests
│   ├── reset_gap_tb.sv      # Reset/gap/back-to-back tests
│   └── ...                  # Additional testbenches
├── tools/                   # Python utilities
│   ├── goertzel_coeffgen.py # Coefficient generator
│   └── gen_goertzel_vectors.py # Regression vector generator
├── coeffs/                  # Generated coefficient metadata
│   ├── science_2p3MHz.json  # Science channel coefficients
│   ├── science_2p3MHz.vh    # Verilog header
│   ├── science_2p3MHz.md    # Human-readable summary
│   ├── pilot_2p4MHz.json    # Pilot channel coefficients
│   └── ...                  # Additional coefficient sets
├── vectors/                 # Generated test vectors
│   ├── tone_phase_00/       # 0° phase coherent tone
│   │   ├── adc.hex          # Stimulus (int16 hex)
│   │   ├── expected.txt     # SV testbench expected values
│   │   └── expected.json    # Rich metadata
│   ├── overflow_alternating # Adversarial overflow test
│   ├── sign_convention_00   # Phase sign verification
│   └── ...                  # 31 total vector directories
├── docs/                    # Documentation
│   ├── fpga_architecture.md # Actuation/measurement separation
│   └── verification_plan.md # Test strategy and coverage
├── run_one_vector.sh        # Single-vector test helper
├── run_regression.sh        # Full regression runner
└── README.md                # This file
```

## Algorithm

The Goertzel core computes one DFT bin via second-order recurrence:

```
s[n] = x[n] + 2*cos(ω)*s[n-1] - s[n-2]

After N samples:
I = s[N] - s[N-1]*cos(ω)
Q = s[N-1]*sin(ω)
```

For coherent cosine tone:
```
Amplitude ≈ 2 * √(I² + Q²) / N_BLOCK
```

**Fixed-Point Format**:
- Coefficients: Q17 (scale = 2¹⁷ = 131,072)
- Internal State: signed 48-bit
- Input/Output: signed 16-bit → signed 48-bit (with overflow checking)

## Verification Flow

1. **Coefficient Generation**: `goertzel_coeffgen.py` produces JSON, .vh, and .md files
2. **Vector Generation**: `gen_goertzel_vectors.py` creates ADC stimuli + golden outputs
3. **RTL Verification**: `goertzel_tb.sv` compares RTL output against Python golden model
4. **Pass Criteria**:
   - Non-overflow: `dout_valid=1`, `overflow_block=0`, exact I/Q match
   - Overflow: `block_done=1`, `overflow_block=1`, `dout_valid=0`

## Stress Test Coverage

| Test Type | Description | Testbench/Vector |
|-----------|-------------|------------------|
| **Coherent Tone** | 8 phase cases, amplitude sweep | `tone_phase_*`, `amp_*` |
| **DC Offset** | ±10k, ±1k, 0 offset | `dc_offset_*` |
| **Noise** | AWGN σ = 0,10,100,1000 | `noise_*` |
| **Off-Bin** | 50 kHz offset | `offbin_plus_50k` |
| **Two-Tone** | Science + 1.1 MHz interferer | `two_tone_interference` |
| **Extremes** | All-negative, near-fullscale | `negative_only`, `near_fullscale` |
| **Overflow** | Alternating ±max amplitude | `overflow_alternating` |
| **Sign Convent.** | Known phase offsets | `sign_convention_0[01]` |
| **Reset/Mid-Blk** | Assert reset at sample 400 | `reset_gap_tb.sv` |
| **din_valid Gaps** | Stall 2 cycles at sample 100 | `reset_gap_tb.sv` |
| **Back-to-Back** | Zero idle cycles between blocks | `reset_gap_tb.sv` |
| **AXI Stall** | 100-cycle `m_axis_tready` stall | `goertzel_axis_tb.sv` |
| **AXI Backpressure** | Withhold `m_axis_tready` during block | `goertzel_axis_tb.sv` |

## Key Design Notes

### Measurement vs. Actuation Separation
This IP belongs strictly to the **measurement path**. It does **not** implement the FIR causal memory kernel used for actuation. Confusing these paths leads to incorrect interpretations of the Goertzel core as implementing physical susceptibility.

### Coherent-Bin Assumption
Current coefficients assume exact coherence: `k = N·fₛ/ fₜ` must be integer. For non-coherent frequencies, use:
- Generalized Goertzel algorithm
- Numerically Controlled Oscillator (NCO) lock-in
- Adjust `N_BLOCK` to achieve coherence

### Overflow Policy
- Intermediate computations use extended width to detect overflow before truncation
- `dout_valid` asserted **only** when block completes without overflow
- Downstream logic must ignore `i_out/q_out` unless `dout_valid == 1`
- `overflow_sticky` remains high until `clear_overflow` asserted

### AXI-Stream Considerations
Current wrapper uses separate `m_axis_i`/`m_axis_q` ports for simplicity. For production:
- Pack I/Q and metadata into single `tdata` bus (96+ bits)
- Use `tuser` for coefficient ID/block index
- Implement proper `tlast` signaling on block boundaries

## Future Work

1. **AXI-Lite Integration**
   - Connect `goertzel_regbank.v` to top-level
   - Add coefficient shadow registers for glitchless updates
   - Implement interrupt output for `block_done`

2. **FPGA Hardening**
   - Add synthesis constraints (XDC/SDC) for target FPGA
   - Generate timing reports and power estimates
   - Pad placement and I/O standards

3. **Enhanced DSP**
   - Integrate CORDIC block for FPGA-side atan2
   - Add magnitude approximation (α·max + β·min)
   - Implement decimation filter for reduced output rate

4. **System Integration**
   - Hardware-in-the-loop test with real ADC/DAC
   - Cross-clock-domain FIFO for asynchronous sampling
   - DMA controller integration for bulk data transfer

5. **Formal Verification**
   - Prove properties with Synopsys VC Formal or Questa Formal
   - Verify reset behavior under all conditions
   - Prove overflow detection completeness

## License

MIT License - see [LICENSE](LICENSE) file for details.

## References

1. Goertzel, G. (1958). *An Algorithm for the Evaluation of Finite Trigonometric Series*. American Mathematical Monthly.
2. Oppenheim, A. V., Schafer, R. W., & Buck, J. R. (1999). *Discrete-Time Signal Processing* (2nd ed.). Prentice Hall.
3. Lyons, R. G. (2010). *Understanding Digital Signal Processing* (3rd ed.). Prentice Hall.

---

*Developed for reproducible research in dynamic Casimir and chiral boundary measurements. Contributions welcome via pull request.*