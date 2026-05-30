#!/usr/bin/env bash
set -euo pipefail
if ! command -v iverilog >/dev/null 2>&1; then
  echo "iverilog not found. Install it or run the listed vectors in Vivado/Questa/Verilator."
  exit 1
fi
mkdir -p outputs
iverilog -g2012 -o outputs/goertzel_tb.vvp rtl/goertzel_core.v tb/goertzel_tb.sv
FAIL=0
while read -r name; do
  [ -z "$name" ] && continue
  echo "===== Running vector: $name ====="
  if ! vvp outputs/goertzel_tb.vvp +VECTOR_DIR=vectors/$name | tee "outputs/${name}.log" | grep -q "VERDICT: PASS"; then
    echo "FAILED: $name"
    FAIL=1
  fi
done < vectors/vector_list.txt
if [ "$FAIL" -ne 0 ]; then
  echo "Regression failed."
  exit 1
fi
echo "Regression passed."
