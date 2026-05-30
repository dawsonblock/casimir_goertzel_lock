#!/usr/bin/env python3
"""
Generate test vectors and expected outputs for goertzel_core.v.

Each vector directory contains:
- adc.hex          signed int16 samples as two's-complement hex
- expected.txt     key-value text consumed by the SystemVerilog testbench
- expected.json    richer metadata for Python/report tooling
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


DEFAULT_FS = 10.0e6
DEFAULT_FREQ = 2.3e6
DEFAULT_N = 1000
DEFAULT_Q_SHIFT = 17
DEFAULT_STATE_BITS = 48


def coeffs(fs: float, freq: float, q_shift: int) -> tuple[int, int, int]:
    omega = 2.0 * math.pi * freq / fs
    return (
        int(round(2.0 * math.cos(omega) * (1 << q_shift))),
        int(round(math.cos(omega) * (1 << q_shift))),
        int(round(math.sin(omega) * (1 << q_shift))),
    )


def assert_signed_width(value: int, bits: int, name: str) -> None:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi:
        raise OverflowError(f"{name} overflow: {value} outside signed {bits}-bit range")


def asr(value: int, shift: int) -> int:
    return value >> shift


def fixed_goertzel(data: np.ndarray, c2: int, c: int, s: int, q_shift: int, state_bits: int) -> dict:
    n_block = len(data)
    s_prev1 = 0
    s_prev2 = 0
    max_abs_state = 0
    overflow = False

    for i in range(n_block - 1):
        x = int(data[i])
        try:
            assert_signed_width(x, 16, f"adc[{i}]")
            feedback = asr(s_prev1 * c2, q_shift)
            s_curr = x + feedback - s_prev2
            assert_signed_width(s_curr, state_bits, f"s[{i}]")
        except OverflowError:
            overflow = True
            # Keep mathematical value for expected overflow metadata.
            feedback = asr(s_prev1 * c2, q_shift)
            s_curr = x + feedback - s_prev2

        s_prev2 = s_prev1
        s_prev1 = s_curr
        max_abs_state = max(max_abs_state, abs(s_curr))

    x_n = int(data[n_block - 1])
    feedback = asr(s_prev1 * c2, q_shift)
    s_n = x_n + feedback - s_prev2
    s_n_minus_1 = s_prev1
    max_abs_state = max(max_abs_state, abs(s_n))

    s1_cos = asr(s_n_minus_1 * c, q_shift)
    s1_sin = asr(s_n_minus_1 * s, q_shift)
    real_bin = s_n - s1_cos
    imag_bin = s1_sin

    for name, value in [("s_N", s_n), ("real_bin", real_bin), ("imag_bin", imag_bin)]:
        try:
            assert_signed_width(value, state_bits, name)
        except OverflowError:
            overflow = True

    return {
        "i_out": int(real_bin),
        "q_out": int(imag_bin),
        "s_n": int(s_n),
        "s_n_minus_1": int(s_n_minus_1),
        "max_abs_state": int(max_abs_state),
        "overflow_expected": bool(overflow),
    }


def export_adc_hex(path: Path, adc: np.ndarray) -> None:
    adc_i16 = np.asarray(adc, dtype=np.int16)
    adc_u16 = adc_i16.view(np.uint16)
    np.savetxt(path, adc_u16, fmt="%04X")


def write_vector(out_dir: Path, name: str, adc: np.ndarray, expected: dict, meta: dict) -> None:
    vec_dir = out_dir / name
    vec_dir.mkdir(parents=True, exist_ok=True)

    export_adc_hex(vec_dir / "adc.hex", adc)

    with (vec_dir / "expected.txt").open("w", encoding="utf-8") as f:
        f.write(f"I_OUT_INTENDED: {expected['i_out']}\n")
        f.write(f"Q_OUT_INTENDED: {expected['q_out']}\n")
        f.write(f"S_N: {expected['s_n']}\n")
        f.write(f"S_N_MINUS_1: {expected['s_n_minus_1']}\n")
        f.write(f"MAX_ABS_STATE: {expected['max_abs_state']}\n")
        f.write(f"OVERFLOW_EXPECTED: {1 if expected['overflow_expected'] else 0}\n")

    payload = {"name": name, **meta, **expected}
    with (vec_dir / "expected.json").open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def generate_vectors(out_dir: Path, fs: float, freq: float, n_block: int, q_shift: int, seed: int) -> None:
    rng = np.random.default_rng(seed)
    c2, c, s = coeffs(fs, freq, q_shift)
    t = np.arange(n_block) / fs
    vectors: list[tuple[str, np.ndarray]] = []

    def adc_from_float(x: np.ndarray) -> np.ndarray:
        return np.clip(np.round(x), -32768, 32767).astype(np.int16)

    for phase_idx, phase in enumerate(np.linspace(0.0, 2.0 * np.pi, 8, endpoint=False)):
        x = 10000.0 * np.cos(2.0 * np.pi * freq * t + phase) + 200.0
        vectors.append((f"tone_phase_{phase_idx:02d}", adc_from_float(x)))

    for amp in [100, 1000, 5000, 12000, 25000]:
        x = amp * np.cos(2.0 * np.pi * freq * t - np.pi / 4) + 100.0
        vectors.append((f"amp_{amp:05d}", adc_from_float(x)))

    for offset in [-10000, -1000, 0, 1000, 10000]:
        x = 6000.0 * np.cos(2.0 * np.pi * freq * t + 0.3) + offset
        vectors.append((f"dc_offset_{offset:+06d}", adc_from_float(x)))

    for noise_sigma in [0, 10, 100, 1000]:
        x = 8000.0 * np.cos(2.0 * np.pi * freq * t - 0.9) + rng.normal(0.0, noise_sigma, n_block)
        vectors.append((f"noise_{noise_sigma:04d}", adc_from_float(x)))

    x = 12000.0 * np.cos(2.0 * np.pi * (freq + 50e3) * t)
    vectors.append(("offbin_plus_50k", adc_from_float(x)))

    x = 7000.0 * np.cos(2.0 * np.pi * freq * t) + 4000.0 * np.cos(2.0 * np.pi * 1.1e6 * t)
    vectors.append(("two_tone_interference", adc_from_float(x)))

    x = np.full(n_block, -12000.0)
    vectors.append(("negative_only", adc_from_float(x)))

    x = 32760.0 * np.cos(2.0 * np.pi * freq * t)
    vectors.append(("near_fullscale", adc_from_float(x)))

    x = 24000.0 * np.cos(2.0 * np.pi * freq * t + 1.23) + 16000.0
    vectors.append(("fullscale_positive", adc_from_float(x)))

    x = np.full(n_block, -32760.0)
    vectors.append(("fullscale_negative", adc_from_float(x)))

    x = np.array([32760.0 if i % 2 == 0 else -32760.0 for i in range(n_block)], dtype=float)
    vectors.append(("overflow_alternating", adc_from_float(x)))

    for phase_idx, phase in enumerate([13.0 / 16.0 * 2.0 * np.pi, 25.0 / 32.0 * 2.0 * np.pi]):
        x = 10000.0 * np.cos(2.0 * np.pi * freq * t + phase) + 200.0
        vectors.append((f"sign_convention_{phase_idx:02d}", adc_from_float(x)))

    meta = {
        "fs_hz": fs,
        "freq_hz": freq,
        "n_block": n_block,
        "q_shift": q_shift,
        "coeff_2cos_q": c2,
        "cos_q": c,
        "sin_q": s,
        "k_exact": n_block * freq / fs,
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    names = []
    for name, adc in vectors:
        expected = fixed_goertzel(adc, c2, c, s, q_shift, DEFAULT_STATE_BITS)
        write_vector(out_dir, name, adc, expected, meta)
        names.append(name)

    with (out_dir / "vector_list.txt").open("w", encoding="utf-8") as f:
        for name in names:
            f.write(name + "\n")

    print(f"Generated {len(names)} vectors in {out_dir}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", type=Path, default=Path("vectors"))
    p.add_argument("--fs", type=float, default=DEFAULT_FS)
    p.add_argument("--freq", type=float, default=DEFAULT_FREQ)
    p.add_argument("--n-block", type=int, default=DEFAULT_N)
    p.add_argument("--q-shift", type=int, default=DEFAULT_Q_SHIFT)
    p.add_argument("--seed", type=int, default=12345)
    args = p.parse_args()
    generate_vectors(args.out_dir, args.fs, args.freq, args.n_block, args.q_shift, args.seed)


if __name__ == "__main__":
    main()
