#!/usr/bin/env bash

set -e

validate_path() {
  local path="$1"
  local name="$2"
  local type="$3"  # "file" or "dir"

  if [[ -z "$path" ]]; then
    echo "ERROR: $name is not set"
    exit 1
  fi

  if [[ "$type" == "file" && ! -f "$path" ]]; then
    echo "ERROR: $name is not a valid file: $path"
    exit 1
  fi

  if [[ "$type" == "dir" && ! -d "$path" ]]; then
    echo "ERROR: $name is not a valid directory: $path"
    exit 1
  fi
}

# ---- CONFIG ----
TRIMMOMATIC_DIR="/pi/thomas.fazzio-umw/conda/pkgs/trimmomatic-0.39-hdfd78af_2/share/trimmomatic-0.39-2"
JAR="$TRIMMOMATIC_DIR/trimmomatic.jar"
ADAPTERS="$TRIMMOMATIC_DIR/adapters/TruSeq3-PE-2.fa"

validate_path "$TRIMMOMATIC_DIR" "TRIMMOMATIC_DIR" dir
validate_path "$JAR" "JAR" file
validate_path "$ADAPTERS" "ADAPTERS" file

# ---- INPUTS ----
R1="$1"
R2="$2"

# ---- CHECK ----
if [[ -z "$R1" || -z "$R2" ]]; then
  echo "Usage: $0 <R1.fastq.gz|fq.gz> <R2.fastq.gz|fq.gz>"
  exit 1
fi

validate_path "$R1" "R1" file
validate_path "$R2" "R2" file

# ---- OUTPUT DIR ----
RESULTS_DIR="./results/01_trim"
mkdir -p "$RESULTS_DIR"

# ---- DERIVE BASENAMES (extension-agnostic) ----
BASE_R1=$(basename "$R1")
BASE_R1=${BASE_R1%.fastq.gz}
BASE_R1=${BASE_R1%.fq.gz}

BASE_R2=$(basename "$R2")
BASE_R2=${BASE_R2%.fastq.gz}
BASE_R2=${BASE_R2%.fq.gz}

# Optional: derive SAMPLE name automatically
SAMPLE=${BASE_R1%_R1_*}

# ---- OUTPUT FILES ----
OUT_R1_P="${RESULTS_DIR}/${BASE_R1}_paired.fq.gz"
OUT_R1_U="${RESULTS_DIR}/${BASE_R1}_unpaired.fq.gz"
OUT_R2_P="${RESULTS_DIR}/${BASE_R2}_paired.fq.gz"
OUT_R2_U="${RESULTS_DIR}/${BASE_R2}_unpaired.fq.gz"

# ---- RUN ----
echo "Running Trimmomatic for $SAMPLE..."
echo

java -jar "$JAR" PE \
  "$R1" "$R2" \
  "$OUT_R1_P" "$OUT_R1_U" \
  "$OUT_R2_P" "$OUT_R2_U" \
  ILLUMINACLIP:"$ADAPTERS":2:25:7:1:true \
  SLIDINGWINDOW:4:10 TRAILING:3 MINLEN:10

echo
echo "Trimming complete for $SAMPLE"
echo "Results written to $RESULTS_DIR"