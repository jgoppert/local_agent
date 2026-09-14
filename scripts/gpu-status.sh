#!/usr/bin/env bash
# One-line GPU temperature, power, memory and utilization readout. Pass "watch" to refresh every 2s.
line() { nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | tr -d ',' | awk -v t="$(date +%H:%M:%S)" '{printf "%s  temp=%sC  power=%.0fW/%.0fW  mem=%s/%sMiB  util=%s%%\n", t, $1, $2, $3, $4, $5, $6}'; }
if [[ "${1:-}" == "watch" ]]; then while true; do line; sleep 2; done; else line; fi
