#!/usr/bin/env bash
# ==============================================================================
# Stage Downstream CUT&RUN Results to Dropbox via rclone
# ==============================================================================
# Reads `experiment` and `rclone_remote` directly from config/experiment.config
# and copies only the outputs needed for QC review and downstream analysis:
#   - 02_multiqc/      (multiqc_original_report.html & multiqc_trimmed_report.html)
#   - 04_dedup/        (*_dup.txt Picard duplication metrics)
#   - 06_index_bam/    (*.bam & *.bam.bai — sorted, deduplicated, MAPQ-filtered BAMs)
#   - 07_homer/        (tag_dir/<sample>/ & UCSC/*.ucsc.bedGraph.gz)
#   - 08_bigwig/       (deepTools/*.bw & UCSC/*.bw)
#   - pipeline_info/   (Nextflow execution reports, timeline, DAG, software versions)
#
# Skipped (large intermediate or redundant files):
#   - 01_trim/         (trimmed FASTQs)
#   - 02_fastqc/       (individual FastQC reports; superseded by MultiQC HTMLs)
#   - 03_align/        (raw Bowtie2 SAM files)
#   - 05_mapq_filter/  (uncompressed SAM files; identical reads are in 06_index_bam/*.bam)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CONFIG_FILE="config/experiment.config"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Error: Configuration file not found at ${CONFIG_FILE}" >&2
    exit 1
fi

EXPERIMENT="$(sed -nE "s/^[[:space:]]*experiment[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*/\1/p" "${CONFIG_FILE}" | head -n 1)"
RAW_REMOTE="$(sed -nE "s/^[[:space:]]*rclone_remote[[:space:]]*=[[:space:]]*[\"']([^\"']+)[\"'].*/\1/p" "${CONFIG_FILE}" | head -n 1)"

if [[ -z "${EXPERIMENT}" ]]; then
    echo "Error: Could not parse 'experiment' from ${CONFIG_FILE}" >&2
    exit 1
fi

# Resolve ${params.experiment} placeholder if present in rclone_remote, or fall back to default
if [[ -n "${RAW_REMOTE}" ]]; then
    REMOTE_DIR="${RAW_REMOTE//\$\{params.experiment\}/${EXPERIMENT}}"
else
    REMOTE_DIR="remote:Walker_lab_shared/Bioinformatics_parent/${EXPERIMENT}"
fi

RESULTS_DIR="./results/${EXPERIMENT}"

if [[ ! -d "${RESULTS_DIR}" ]]; then
    echo "Error: Results directory not found at ${RESULTS_DIR}" >&2
    exit 1
fi

RCLONE_FLAGS=(-P -vv "$@")

echo "========================================================================"
echo " Staging CUT&RUN Results to Dropbox"
echo "------------------------------------------------------------------------"
echo " Experiment  : ${EXPERIMENT}"
echo " Local Path  : ${RESULTS_DIR}"
echo " Remote Path : ${REMOTE_DIR}"
echo "========================================================================"

# 1. MultiQC summary reports (raw and trimmed HTML reports only)
if [[ -d "${RESULTS_DIR}/02_multiqc" ]]; then
    echo "-> Copying 02_multiqc HTML reports..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/02_multiqc" "${REMOTE_DIR}/02_multiqc/" \
        --include "multiqc_original_report.html" \
        --include "multiqc_trimmed_report.html"
fi

# 2. Picard duplication metrics (*_dup.txt for library complexity / FRiP QC)
if [[ -d "${RESULTS_DIR}/04_dedup" ]]; then
    echo "-> Copying 04_dedup Picard metrics (*_dup.txt)..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/04_dedup" "${REMOTE_DIR}/04_dedup/" \
        --include "*_dup.txt"
fi

# 3. Coordinate-sorted, deduplicated, MAPQ-filtered BAMs & BAI indices
if [[ -d "${RESULTS_DIR}/06_index_bam" ]]; then
    echo "-> Copying 06_index_bam (*.bam and *.bam.bai)..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/06_index_bam" "${REMOTE_DIR}/06_index_bam/" \
        --include "*.bam" \
        --include "*.bam.bai"
fi

# 4. HOMER tag directories (tag_dir/<sample>/) & UCSC bedGraph tracks
if [[ -d "${RESULTS_DIR}/07_homer" ]]; then
    echo "-> Copying 07_homer (tag_dir/ and *.ucsc.bedGraph.gz)..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/07_homer" "${REMOTE_DIR}/07_homer/"
fi

# 5. BigWig signal tracks (deepTools RPKM and UCSC bedGraphToBigWig)
if [[ -d "${RESULTS_DIR}/08_bigwig" ]]; then
    echo "-> Copying 08_bigwig (deepTools/ and UCSC/)..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/08_bigwig" "${REMOTE_DIR}/08_bigwig/"
fi

# 6. Pipeline execution telemetry & software versions
if [[ -d "${RESULTS_DIR}/pipeline_info" ]]; then
    echo "-> Copying pipeline_info..."
    rclone copy "${RCLONE_FLAGS[@]}" \
        "${RESULTS_DIR}/pipeline_info" "${REMOTE_DIR}/pipeline_info/"
fi

echo "========================================================================"
echo " Dropbox staging complete: ${REMOTE_DIR}"
echo "========================================================================"
