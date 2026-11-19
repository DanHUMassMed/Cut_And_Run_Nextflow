#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $(basename "$0") <outdir> <rclone_remote> <log_file> [rclone_args...]" >&2
    exit 1
fi

OUTDIR="$1"
RCLONE_REMOTE="$2"
LOG_FILE="$3"
shift 3
RCLONE_ARGS=("$@")

if [[ ${#RCLONE_ARGS[@]} -eq 0 ]]; then
    RCLONE_ARGS=(--transfers 4 --checkers 8 -v)
fi

if ! command -v rclone >/dev/null 2>&1; then
    echo "ERROR: rclone not found in PATH." >&2
    exit 1
fi

if [[ ! -d "${OUTDIR}" ]]; then
    echo "ERROR: Results directory not found: ${OUTDIR}" >&2
    exit 1
fi

sync_dir() {
    local subdir="$1"
    local include_pattern="$2"
    if [[ -d "${OUTDIR}/${subdir}" ]]; then
        rclone copy "${RCLONE_ARGS[@]}" \
            "${OUTDIR}/${subdir}" \
            "${RCLONE_REMOTE}/${subdir}/" \
            --include "${include_pattern}"
    fi
}

{
    echo "Staging results from ${OUTDIR} -> ${RCLONE_REMOTE}"

    sync_dir "01_trim"       "*_trimmomatic.log"
    sync_dir "02_fastqc"     "**/*"
    sync_dir "02_multiqc"    "*.html"
    sync_dir "02_multiqc"    "**/*"
    sync_dir "03_align"      "*_bowtie2.log"
    sync_dir "04_dedup"      "*_dup.txt"
    sync_dir "06_bam_stats"  "**/*"
    sync_dir "07_homer"      "**/*"
    sync_dir "08_deeptools"  "**/*"
    sync_dir "pipeline_info" "**/*"

    echo "Dropbox staging complete."
} 2>&1 | tee "${LOG_FILE}"
