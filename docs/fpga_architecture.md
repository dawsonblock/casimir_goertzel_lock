# FPGA Architecture Notes

## Correct partition

The FIR causal memory kernel and the Goertzel lock-in detector serve different roles.

The FIR belongs to the actuation/control path. It represents the engineered causal susceptibility approximation and should not be replaced by Goertzel.

The Goertzel core belongs to the measurement path. It extracts science and pilot phasors at coherent bins.

## Recommended full system

```text
                 +---------------------+
                 | ARM / control plane |
                 | atan2, calibration  |
                 | coeff IDs, logging  |
                 +----------+----------+
                            |
                            v
ADC -> science Goertzel -> I/Q science -----> correction matrix -> DMA/statistics
   \-> pilot Goertzel ----> I/Q pilot -----> phase drift estimator

Actuation: FIR kernel -> DAC -> actuator / boundary channel
```

## Pilot phase tracking

Choose pilot frequencies coherent with block size. For `fs=10 MHz`, `N=1000`:

- `2.30 MHz` => `k=230`
- `2.40 MHz` => `k=240`
- `2.20 MHz` => `k=220`
- `2.35 MHz` => `k=235`

Avoid noncoherent pilot frequencies unless the readout uses generalized Goertzel or an NCO lock-in.

## Phase-leakage reminder

The dominant systematic is static phase leakage:

```math
Q_{leak} \approx I\sin(\delta\phi)
```

The Goertzel core reduces deterministic digital extraction error, but it does not by itself solve analog phase drift, actuator dispersion, or static lock-in reference error.
