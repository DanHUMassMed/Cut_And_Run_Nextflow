# Implementation Plan: Upstream QC Logs, BAM Stats, Unified MultiQC & Dropbox Staging (`Cut_And_Run_Nextflow`)

This plan covers four additions to `Cut_And_Run_Nextflow` (active development — no backward-compatibility shims required):

1. **Emit & publish tool logs** (`*_bowtie2.log`, `*_trimmomatic.log`).
2. **Add `SAMTOOLS_BAM_STATS`** (`samtools flagstat`, `samtools idxstats`, `samtools stats`) on final indexed BAMs.
3. **Add `MULTIQC_ALL`** combining FastQC (raw & trimmed), Trimmomatic, Bowtie2, Picard (`*_dup.txt`), and samtools stats into a single HTML report.
4. **Add `RCLONE_STAGE_DROPBOX`** (`params.run_stage_results_dropbox`) to copy published results to `${params.rclone_remote}` via `rclone` once all active pipeline steps finish.

---

## Architecture Overview

```text
FASTQ ──► FASTQC_RAW ───────────────────────────────────────────┐
      └──► TRIMMOMATIC ──► (*_trimmomatic.log) ─────────────────┤
              └──► FASTQC_TRIMMED ──────────────────────────────┤
              └──► BOWTIE2_ALIGN ──► (*_bowtie2.log) ───────────┼──► MULTIQC_ALL
                      └──► PICARD_DEDUP ──► (*_dup.txt) ────────┤    (02_multiqc/multiqc_all_report.html)
                              └──► SAMTOOLS_MAPQ_FILTER         │          │
                                      └──► DEEPTOOLS_BAM_BW     │          │
                                              ├──► SAMTOOLS_BAM_STATS ─────┤
                                              └──► HOMER_TAG_DIR / UCSC_BW │
                                                                           ▼
                                                        [ Barrier: all active outputs ]
                                                                           │
                                                                           ▼
                                                               RCLONE_STAGE_DROPBOX
                                                               (${params.rclone_remote})
```

### Key Design Decisions
- **Dedicated `SAMTOOLS_BAM_STATS` module:** Clean Single Responsibility, fast execution, and allows running `SAMTOOLS_BAM_STATS` + `MULTIQC_ALL` directly on existing BAMs (`08_deeptools/bam_index/*.bam`) without regenerating BigWigs.
- **Direct `MULTIQC` signature update:** Update `modules/local/multiqc/main.nf` cleanly to accept `path multiqc_config` (used by `MULTIQC_ALL`, `[]` for `MULTIQC_RAW`/`MULTIQC_TRIMMED`).
- **In-pipeline Dropbox staging (`RCLONE_STAGE_DROPBOX`):** Replaces manual `sync_to_dropbox.sh` invocations with a gated Nextflow process that runs after all active upstream tasks finish, uses host `rclone` (so `~/.config/rclone/rclone.conf` and OAuth tokens work without container auth hacks), and disables caching (`cache = false`) so re-runs always sync new outputs.

---

## Phase 1: Emit & Publish Trimmomatic and Bowtie2 Logs

### 1.1 `modules/local/bowtie2/main.nf`
Both `script:` and `stub:` already create `${prefix}_bowtie2.log`. Add it to `output:`:

```groovy
output:
tuple val(meta), path("${prefix}_align.sam")  , emit: sam
tuple val(meta), path("${prefix}_bowtie2.log"), emit: log
tuple val("${task.process}"), val('bowtie2'), eval("(bowtie2 --version 2>&1 || true) | sed -n 's/.*bowtie2-align-s version //p'"), emit: versions_bowtie2, topic: versions
```

### 1.2 `modules/local/trimmomatic/main.nf`
Both `script:` and `stub:` already create `${prefix}_trimmomatic.log`. Add it to `output:`:

```groovy
output:
tuple val(meta), path("*_paired.fq.gz")           , emit: paired_reads
tuple val(meta), path("${prefix}_trimmomatic.log"), emit: log
tuple val("${task.process}"), val('trimmomatic'), eval("trimmomatic -version 2>/dev/null || echo '0.39'"), emit: versions_trimmomatic, topic: versions
```

### 1.3 `conf/modules.config`
- `TRIMMOMATIC` already publishes to `${params.outdir}/01_trim` → `*_trimmomatic.log` publishes automatically.
- `BOWTIE2_ALIGN` already publishes to `${params.outdir}/03_align` → `*_bowtie2.log` publishes automatically.

---

## Phase 2: Add `SAMTOOLS_BAM_STATS` Module

### 2.1 Create `modules/local/samtools/stats/environment.yml`
```yaml
---
channels:
  - conda-forge
  - bioconda
dependencies:
  - bioconda::samtools=1.21
```

### 2.2 Create `modules/local/samtools/stats/main.nf`
```groovy
process SAMTOOLS_BAM_STATS {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/87/87660348a4d032cc08d6ac8101ff9d4d27164300d39c9472043bb5001f9ba801/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.25--704fb80d75745bd4'}"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("${prefix}.flagstat"), emit: flagstat
    tuple val(meta), path("${prefix}.idxstats"), emit: idxstats
    tuple val(meta), path("${prefix}.stats")   , emit: stats
    tuple val("${task.process}"), val('samtools'), eval("(samtools --version 2>&1 || true) | sed '1!d;s/^.*samtools //'"), emit: versions_samtools, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools flagstat -@ ${task.cpus} "${bam}" > "${prefix}.flagstat"
    samtools idxstats "${bam}" > "${prefix}.idxstats"
    samtools stats -@ ${task.cpus} "${bam}" > "${prefix}.stats"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.flagstat"
    touch "${prefix}.idxstats"
    touch "${prefix}.stats"
    """
}
```

### 2.3 Configure publishing in `conf/modules.config`
```groovy
withName: 'SAMTOOLS_BAM_STATS' {
    publishDir = [
        path: { "${params.outdir}/06_bam_stats" },
        mode: params.publish_dir_mode
    ]
}
```

---

## Phase 3: Add Unified `MULTIQC_ALL` Process & Config

### 3.1 Create `assets/multiqc_config.yaml`
Aligns sample names across all 6 tools so each sample appears as a single clean row in General Statistics:

```yaml
title: "CUT&RUN Upstream QC Summary"
subtitle: "Combined FastQC, Trimmomatic, Bowtie2, Picard, and Samtools QC"

trimmomatic:
  s_name_filenames: true

extra_fn_clean_exts:
  - "_bowtie2"
  - "_trimmomatic"
  - "_dup"
  - "_paired"

module_order:
  - fastqc:
      name: "FastQC (Raw)"
      path_filters:
        - "*_R1_*.zip"
        - "*_R2_*.zip"
      path_filters_exclude:
        - "*_paired*"
  - trimmomatic
  - fastqc:
      name: "FastQC (Trimmed)"
      path_filters:
        - "*_paired*"
  - bowtie2
  - picard
  - samtools
```

### 3.2 Update `modules/local/multiqc/main.nf`
Add `path multiqc_config` directly to `input:`:

```groovy
input:
tuple val(meta), path(multiqc_files, stageAs: "?/*")
path multiqc_config
```

```groovy
script:
def args       = task.ext.args ?: ''
def prefix     = task.ext.prefix ?: "${meta.id}"
def config_arg = multiqc_config ? "--config ${multiqc_config}" : ''
"""
multiqc \\
    --force \\
    --filename ${prefix}.html \\
    ${config_arg} \\
    ${args} \\
    .
"""
```

### 3.3 Configure `MULTIQC_ALL` in `conf/modules.config`
```groovy
withName: 'MULTIQC_ALL' {
    ext.prefix = 'multiqc_all_report'
    publishDir = [
        path: { "${params.outdir}/02_multiqc" },
        mode: params.publish_dir_mode
    ]
}
```

---

## Phase 4: Add `RCLONE_STAGE_DROPBOX` Module (`run_stage_results_dropbox`)

### 4.1 Create `bin/stage_results_dropbox.sh` (`chmod +x`)
Nextflow automatically adds `${projectDir}/bin/` to `$PATH` for every process. Keeping the sync logic in `bin/stage_results_dropbox.sh` makes it easy to update synced directories/include filters in one place and allows running the script standalone for debugging:

```bash
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
    sync_dir "02_multiqc"    "**/*"
    sync_dir "03_align"      "*_bowtie2.log"
    sync_dir "04_dedup"      "*_dup.txt"
    sync_dir "06_bam_stats"  "**/*"
    sync_dir "07_homer"      "**/*"
    sync_dir "08_deeptools"  "**/*"
    sync_dir "pipeline_info" "**/*"

    echo "Dropbox staging complete."
} 2>&1 | tee "${LOG_FILE}"
```

### 4.2 Create `modules/local/rclone/stage_dropbox/main.nf`
- Runs on the host environment (`executor = 'local'`, `container = null` so host `rclone` and `~/.config/rclone/rclone.conf` are used directly).
- Takes `val(ready_token)` (a collected barrier from all active upstream channels so it executes **only after** all steps have completed and published to `${outdir}`), `val(outdir)`, and `val(rclone_remote)`.
- Uses `cache false` so enabling `run_stage_results_dropbox = true` always syncs fresh/updated results.
- Calls `stage_results_dropbox.sh` directly from `bin/`:

```groovy
process RCLONE_STAGE_DROPBOX {
    tag "${params.experiment}"
    label 'process_single'
    cache false

    input:
    val ready_token
    val outdir
    val rclone_remote

    output:
    path "rclone_dropbox_sync.log", emit: log
    tuple val("${task.process}"), val('rclone'), eval("(rclone version 2>/dev/null | head -n 1 | awk '{print \$2}') || echo 'unknown'"), emit: versions_rclone, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: '--transfers 4 --checkers 8 -v'
    """
    stage_results_dropbox.sh \\
        "${outdir}" \\
        "${rclone_remote}" \\
        "rclone_dropbox_sync.log" \\
        ${args}
    """

    stub:
    """
    echo "STUB: Would stage ${outdir} -> ${rclone_remote}" > rclone_dropbox_sync.log
    """
}
```

### 4.3 Configure `RCLONE_STAGE_DROPBOX` in `conf/modules.config`
```groovy
withName: 'RCLONE_STAGE_DROPBOX' {
    executor   = 'local'
    container  = null
    publishDir = [
        path: { "${params.outdir}/pipeline_info" },
        mode: params.publish_dir_mode
    ]
}
```

> **HPC note:** Setting `executor = 'local'` ensures `rclone` runs on the submit/login node (which has internet access and `~/.config/rclone/rclone.conf`), rather than on an air-gapped LSF compute node. If your HPC allows outbound internet on compute nodes and you want LSF scheduling, remove `executor = 'local'` or override it in `experiment.config`.

---

## Phase 5: Wire Parameters, Channels, and Workflow

### 5.1 `nextflow.config`
Add toggles and config path under `params`:

```groovy
run_bam_stats                  = false
run_multiqc_all                = false
run_stage_results_dropbox      = false
multiqc_config                 = "${projectDir}/assets/multiqc_config.yaml"
```

### 5.2 `main.nf`
1. Fail fast if `params.run_stage_results_dropbox` is `true` and `!params.rclone_remote`:
   ```groovy
   if (params.run_stage_results_dropbox && !params.rclone_remote) {
       error("params.rclone_remote must be set when params.run_stage_results_dropbox = true.")
   }
   ```
2. Add `bam_stats`, `multiqc_all`, and `stage_results_dropbox` to the startup `log.info` banner.
3. Add existing-file fallback channels for retroactive/partial runs:
   - `ch_existing_bam_bai`: resolved from `"${params.outdir}/08_deeptools/bam_index/*.bam"` paired with `${bam}.bai`.
   - Existing QC file channels from `${params.outdir}` (`02_fastqc/original/*.zip`, `01_trim/*_trimmomatic.log`, `02_fastqc/trimmed/*.zip`, `03_align/*_bowtie2.log`, `04_dedup/*_dup.txt`, `06_bam_stats/*.{flagstat,idxstats,stats}`).
4. Pass them into `CUTANDRUN_BASE(...)`.

### 5.3 `workflows/cutandrun_base.nf`
1. Import new modules:
   ```groovy
   include { SAMTOOLS_BAM_STATS     } from '../modules/local/samtools/stats/main'
   include { MULTIQC as MULTIQC_ALL } from '../modules/local/multiqc/main'
   include { RCLONE_STAGE_DROPBOX   } from '../modules/local/rclone/stage_dropbox/main'
   ```
2. Pass `[]` as the second argument to `MULTIQC_RAW(ch_raw_multiqc_in, [])` and `MULTIQC_TRIMMED(ch_trimmed_multiqc_in, [])`.
3. Capture `TRIMMOMATIC.out.log` and `BOWTIE2_ALIGN.out.log`.
4. Add **Step 06b (`SAMTOOLS_BAM_STATS`)**:
   - Consumes `params.run_deeptools_bam_bw ? ch_bam_bai : ch_existing_bam_bai`.
5. Add **Step 09 (`MULTIQC_ALL`)**:
   - Collects live outputs from steps enabled in this run (falling back to existing published QC files for skipped steps), passes `file(params.multiqc_config, checkIfExists: true)`.
6. Add **Step 10 (`RCLONE_STAGE_DROPBOX`)**:
   - Build a completion barrier channel collecting outputs from all active steps:
     ```groovy
     if (params.run_stage_results_dropbox) {
         def ch_stage_barrier = channel.empty()
             .mix(
                 ch_raw_multiqc,
                 ch_trimmed_multiqc,
                 ch_trimmomatic_log,
                 ch_bowtie2_log,
                 ch_dedup_metrics,
                 ch_bam_bai,
                 ch_rpkm_bw,
                 ch_bam_stats,
                 ch_tagdir,
                 ch_ucsc_bw,
                 ch_multiqc_all,
                 ch_collated_versions
             )
             .collect()
             .ifEmpty(['ready'])

         RCLONE_STAGE_DROPBOX(
             ch_stage_barrier,
             params.outdir,
             params.rclone_remote
         )
     }
     ```
7. Emit `trimmomatic_log`, `bowtie2_log`, `bam_flagstat`, `bam_idxstats`, `bam_stats`, `multiqc_all`, and `dropbox_sync_log`.

---

## Verification Plan

1. **Stub Test (`-stub-run`)**:
   - Run Nextflow with `-stub-run` enabling all toggles including `run_bam_stats = true`, `run_multiqc_all = true`, and `run_stage_results_dropbox = true`.
   - Verify expected published files:
     - `01_trim/*_trimmomatic.log`
     - `03_align/*_bowtie2.log`
     - `06_bam_stats/*.flagstat`, `*.idxstats`, `*.stats`
     - `02_multiqc/multiqc_all_report.html`
     - `pipeline_info/rclone_dropbox_sync.log`
   - Verify `RCLONE_STAGE_DROPBOX` runs **last** in the execution DAG (`pipeline_info/pipeline_dag_*.html`).
2. **Fail-Fast Validation Test**:
   - Run with `run_stage_results_dropbox = true` and `rclone_remote = null` → confirm immediate error before any process launches.
3. **Retroactive BAM + MultiQC Test (on `cut_run103026B`)**:
   - Run with `run_bam_stats = true`, `run_multiqc_all = true`, `run_stage_results_dropbox = false` against existing `08_deeptools/bam_index/*.bam` and `04_dedup/*_dup.txt`.
   - Confirm `06_bam_stats/` populates for all 5 samples and `02_multiqc/multiqc_all_report.html` merges Picard + Samtools rows cleanly per sample ID.
4. **Live Dropbox Staging Test**:
   - Run with `run_stage_results_dropbox = true` and verify `02_multiqc/multiqc_all_report.html`, `06_bam_stats/`, `07_homer/`, and `08_deeptools/` appear at `${params.rclone_remote}` and `pipeline_info/rclone_dropbox_sync.log` is recorded.
