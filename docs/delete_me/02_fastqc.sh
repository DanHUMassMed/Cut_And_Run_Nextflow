#!/usr/bin/env bash

set -e

# ---- INPUT ----
R1="$1"
R2="$2"

# ---- CHECK ----
if [[ -z "$R1" || -z "$R2" ]]; then
  echo "Usage: $0 <R1_paired.fq.gz> <R2_paired.fq.gz>"
  exit 1
fi

if [[ ! -f "$R1" ]]; then
  echo "ERROR: File not found: $R1"
  exit 1
fi

if [[ ! -f "$R2" ]]; then
  echo "ERROR: File not found: $R2"
  exit 1
fi

# ---- LOAD MODULE ----
module load fastqc/0.11.9

# ---- OUTPUT DIR ----
OUT_DIR="./results/02_fastqc"
mkdir -p "$OUT_DIR"

# ---- RUN ----
echo "Running FastQC on:"
echo "  $R1"
echo "  $R2"

fastqc "$R1" -o "$OUT_DIR"
fastqc "$R2" -o "$OUT_DIR"

echo "FastQC complete"