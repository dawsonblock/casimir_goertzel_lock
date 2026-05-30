#!/usr/bin/env bash
set -euo pipefail
VECTOR_DIR=${1:-vectors/tone_phase_00}
SIM=${SIM:-iverilog}
if command -v iverilog >/dev/null 2>&1; then
  iverilog -g2012 -o outputs/goertzel_tb.vvp rtl/goertzel_core.v tb/goertzel_tb.sv
  vvp outputs/goertzel_tb.vvp +VECTOR_DIR=${VECTOR_DIR}
else
  echo "iverilog not found. Use your simulator with rtl/goertzel_core.v and tb/goertzel_tb.sv."
  exit 1
fi
