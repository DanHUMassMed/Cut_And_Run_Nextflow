# Code & Bioinformatics Review: `Cut_And_Run_Nextflow` (`cutandrun-base` v1.0.0)

> **Generated with:** `seqera-cli-agent` (`seqera ai --headless`, Seqera CLI v1.14.0)  
> **Date:** 2026-11-22  
> **Scope:** `main.nf`, `nextflow.config`, `workflows/cutandrun_base.nf`, `conf/base.config`, `conf/modules.config`, `lib/utils.nf`, all `modules/local/**`, plus `bin/stage_results_dropbox.sh`, `assets/multiqc_config.yaml`, `test.nf`, and `docs/Example_Run/config/experiment.config` where they affect behaviour.  
> **Verification:** `nextflow lint .` passes under Nextflow 26.10.0 with 0 errors and 11 warnings (all for the deprecated `when:` block). No pipeline files were modified.

---

## Executive summary

The pipeline is tidy and modern for a lab pipeline. It passes strict-syntax (v2) lint, uses topic-channel version collection, pins Wave or BioContainers images by digest, and every module has a stub. The main risks are:

1. **Silent no-op runs.** The example config uses toggle names that no longer exist. Missing inputs give empty channels instead of errors.
2. **Bowtie2 ignores its staged index.** It reads a hard-coded host path, which breaks Docker and any non-shared-FS executor.
3. **The samplesheet is effectively mandatory,** although the README says it's optional.
4. **Dropbox staging can race the publishing step,** and its include filters probably skip flat directories.
5. **The CUT&RUN method has gaps:** no fragment-aware coverage, no proper-pair filtering, no spike-in or blacklist handling, and unconditional duplicate removal.
6. **Retries don't add resources,** and there are no time limits or resource caps.

---

## 1. Nextflow DSL2 architecture, channel wiring & best practices

### Strengths
- The layout is clean: entry `main.nf` → `workflows/cutandrun_base.nf` → `modules/local/*`, with helpers in `lib/utils.nf`.
- It's ready for strict syntax: explicit closure params, lowercase `channel.*`, `def` everywhere, and no `Channel.from`.
- Software versions come from topic channels (`topic: versions`) with `eval()` outputs. That is the current recommended pattern for 25.10+.
- Every module has a `stub:` block, so `-stub-run` works.
- `ext.args` / `ext.prefix` are set in `conf/modules.config`, following nf-core convention.

### Issues

| # | Location | Finding |
|---|----------|---------|
| A1 | All `modules/local/**/main.nf` (`when:` blocks) | `when:` is deprecated (11 lint warnings). The workflow already gates every call with `if (params.run_*)`, so the `when:` blocks are dead code. Remove them. |
| A2 | `main.nf:11-12` | `extractSampleId` and `buildMeta` are imported but never used in `main.nf`. |
| A3 | `main.nf:120` | `workflow.onComplete = { … }` is assigned inside the entry workflow. On 25.10+ the idiomatic form is an `onComplete:` section in the entry workflow, or a handler in config. |
| A4 | `main.nf:79-89`, `lib/utils.nf:86-106` | The fallback channels (`ch_existing_*`) are built and their `.map { buildMeta(...) }` runs **even when the matching step is enabled**. Nextflow operators run whether or not anything consumes them. So a stale or foreign file in `outdir` (for example a BAM not in the samplesheet) calls `error` and aborts an otherwise valid run. `resolveBamBai` also uses `checkIfExists: true` on the `.bai`. Only build fallbacks when the step is off. |
| A5 | `workflows/cutandrun_base.nf:185,193,329` | `ch_existing_bedgraph` and `ch_bedgraph` are only re-emitted, never consumed. The glob at `main.nf:69,89` is dead work. |
| A6 | `workflows/cutandrun_base.nf:174-190` | The restart model is inconsistent. Every step falls back to published outputs except HOMER: `run_homer_ucsc_bw=true` with `run_homer_tag_dir=false` silently does nothing because `ch_tagdir` is empty. |
| A7 | `workflows/cutandrun_base.nf:77,114,140,151` | No step checks that its input exists. Examples: `run_trimmomatic=true` with `input_fastq=null`, or `run_bowtie2_align=true` with Trimmomatic off and no `input_trimmed_fastq`. Either produces an empty channel and a "successful" run with no output. Add up-front checks in `main.nf`. |
| A8 | Whole design | Step skipping works by re-reading files from `outdir`. That duplicates `-resume`, forces huge intermediates (SAM files) to be published, and ties correctness to publish naming. Consider relying on `-resume` and keeping only real entry points (FASTQ, BAM). |
| A9 | `modules/local/deeptools/main.nf:32-34` | One process does SAM→BAM conversion, indexing **and** bamCoverage. So `SAMTOOLS_BAM_STATS` depends on `run_deeptools_bam_bw` (`cutandrun_base.nf:159`), and you can't get an indexed BAM without a BigWig. Split it into `SAMTOOLS_VIEW`/`INDEX` and `DEEPTOOLS_BAMCOVERAGE`. The header comment ("Indexes a BAM file using samtools index") is also misleading. |
| A10 | `modules/local/samtools/main.nf` + `modules/local/samtools/stats/main.nf` | There's a module `main.nf` both in `samtools/` and in the nested `samtools/stats/`. nf-core layout forbids nesting a module inside another module's directory. Rename to `samtools/mapqfilter/` and `samtools/bamstats/`. |
| A11 | `modules.json` | It declares nf-core repos but has no installed modules. Every stage here already exists in nf-core/modules: `trimmomatic`, `bowtie2/align`, `picard/markduplicates`, `samtools/view|index|flagstat|idxstats|stats`, `deeptools/bamcoverage`, `homer/maketagdirectory`, `homer/makeucscfile`, `ucsc/bedgraphtobigwig`, `fastqc`, `multiqc`. Reusing them would cut maintenance and fix several issues below. nf-core/cutandrun is also worth benchmarking against. |
| A12 | `nextflow.config` `params {}` | `params.outdir` is used everywhere but never declared with a default. Typos in experiment configs pass silently. `.gitignore` already contains `null/`, which suggests output has gone to a `null/` directory before. There's no `nextflow_schema.json` or typed `params {}` block (stable in 26.04), so nothing validates input. `params.help` and `params.email` are declared but unused. |
| A13 | `main.nf:28` | `params.fastq_dir` is required but only used by the Docker `runOptions` and the example's `input_fastq`. The real input is `input_fastq`. Validate that instead, or derive it. |
| A14 | `workflows/cutandrun_base.nf:264` | `tool_versions.unique().sort()` works only because both methods mutate the list in place; the return value is thrown away. Write `def tv = tool_versions.unique().sort()` instead. |
| A15 | `workflows/cutandrun_base.nf:270-275` | `software_mqc_versions.yml` is written to `pipeline_info` but never passed to `MULTIQC_ALL`, so the MultiQC report has no software-versions section. |
| A16 | `test.nf` | This is a repo-root scratch file that duplicates `lib/utils.nf`, uses `nextflow.enable.dsl = 2` and is full of `.view` calls. Remove it, or replace it with nf-test plus a `test` profile that runs `-stub`. There's also no CI. |

---

## 2. Containerization, reproducibility & version pinning

### Strengths
- Images are pinned by Wave digest or BioContainers build tag, and Singularity pulls https blobs directly (nf-core style).
- Each module has an `environment.yml`.

### Issues

| # | Location | Finding |
|---|----------|---------|
| C1 | `modules/local/samtools/environment.yml`, `samtools/stats/environment.yml` vs `main.nf:7-8` | Conda pins **samtools 1.21**, but the container is `htslib_samtools:1.25`. Conda and container runs use different versions. The same likely applies to `bowtie2` and `deeptools`: their envs pin samtools 1.21, and the container contents can't be verified from the tag. Rebuild images from the env files, or align the pins. |
| C2 | `modules/local/picard/environment.yml`, `picard/main.nf:8` | **Picard 2.5.0 dates from 2016.** Bioconda's latest is 3.5.0. Upgrade, ideally via nf-core `picard/markduplicates`. The `--version` probe at line 16 may return an empty string on 2.5.0 (low confidence). |
| C3 | `modules/local/homer/tag_dir/main.nf:8` | The HOMER container is `bioconductor-deseq2_bioconductor-edger_homer_samtools_pruned`: a large image carrying DESeq2 and edgeR. It doesn't match `environment.yml` (homer and samtools only). |
| C4 | `modules/local/homer/ucsc_bw/environment.yml` | Includes `conda-forge::gocryptfs=2.6.1`, an encrypted-filesystem tool unrelated to this step. Looks accidental; remove it and rebuild. |
| C5 | `homer/tag_dir/main.nf:15`, `homer/ucsc_bw/main.nf:17-18` | Versions are hard-coded (`val('4.11')`, `val('482')`), so the report doesn't reflect what actually ran. Note that HOMER 5.1 is on Bioconda. |
| C6 | `trimmomatic/main.nf:17` | `trimmomatic -version 2>/dev/null \|\| echo '0.39'` hides a failed probe behind a made-up version. |
| C7 | `trimmomatic/main.nf:43-50` | Falls back to `find /usr/local/share /opt/conda/share` for adapters. The adapter file is already a staged `path` input that's checked at `cutandrun_base.nf:79`, so this branch can't usefully fire. Remove it. |
| C8 | `modules/local/rclone/stage_dropbox/main.nf` + `modules.config` | No container or conda; it depends on `rclone` being on the host PATH. That's acceptable for a local-executor step, but document it. |
| C9 | `nextflow.config` | There's no `conda` profile despite the `environment.yml` files. No `singularity.cacheDir` is set, so on HPC each run may pull images into `work/`. Set `NXF_SINGULARITY_CACHEDIR` or `singularity.cacheDir`. |
| C10 | `nextflow.config:89` | `includeConfig "${launchDir}/config/experiment.config"` is mandatory. Launching from any other directory, from Seqera Platform, or with `nextflow run <repo>` fails at config parse. `run.sh` also passes `-c config/experiment.config`, so the file is loaded twice. Remove the hard include and rely on `-c`/`-params-file`. |
| C11 | `nextflow.config:160` | `manifest.homePage` points to the downstream `Cut_And_Run_Analysis` repo, not this one. |

---

## 3. Resources, LSF/local profiles, publishDir & error strategy

| # | Location | Finding |
|---|----------|---------|
| R1 | `conf/base.config:16-17` | Retries keep the same resources: no `task.attempt` scaling and `maxRetries = 1`. Retrying an OOM or wall-time kill (130–145) with identical memory, CPUs and queue will usually fail again. Use `memory = { 32.GB * task.attempt }` and similar. |
| R2 | `conf/base.config` | No `time` directive, so jobs inherit the `short` queue's wall limit. Large Bowtie2 or Picard jobs on `process_medium`/`short` can hit the run limit. Add `time` per label and move to `long` on retry. |
| R3 | `conf/base.config` | No `process.resourceLimits`. Under `-profile local` on a laptop, `process_high` (8 CPU / 56 GB) is requested as-is. |
| R4 | `conf/base.config:13-41` | CPUs are strings (`'4'`) and memory uses `'24G'` strings. Use integers and `24.GB`. |
| R5 | `nextflow.config` | There's no `executor {}` block for LSF: no `queueSize`, `submitRateLimit` or `perJobMemLimit`/`perTaskReserve`. Whether Nextflow passes `-M` per job or per slot depends on the site's `lsf.conf`; confirm with the UMass HPC team and set it explicitly. |
| R6 | Labels | CPU waste: Picard (`process_medium`, 6 CPU) and `makeTagDirectory` (`process_medium`) are essentially single-threaded. Move them to `process_single` or `process_low`. `samtools view -@ ${task.cpus}` adds threads on top of the main one, so pass `task.cpus - 1`. |
| R7 | `nextflow.config:107` | The Docker profile mounts `-v '${params.fastq_dir}:${params.fastq_dir}'`. The example's `fastq_dir = "data/fastq"` is relative, which gives Docker an invalid volume spec. The Bowtie2 index on `/share/...` isn't mounted either (see B2). |
| R8 | `nextflow.config:97,129` | `configProcessNamesValidation = false` is set at top level *after* the `profiles` block. It may override the `debug` profile's `true` (low confidence; depends on config evaluation order). |
| P1 | `conf/modules.config:59-64,82-88` | Uncompressed **SAM** files are published to `03_align` and `05_mapq_filter` with `mode: 'copy'`. That roughly doubles the largest files on disk. Emit BAM or CRAM, and don't publish intermediates unless needed. |
| P2 | `conf/modules.config:66-79` | Two publishDir entries point to the same directory. One entry with `pattern: "*_{dup.txt,dedup.bam}"` does the same job. |
| P3 | `conf/modules.config:14-18` | The default `saveAs` filter for `versions.yml` is legacy; topic channels no longer emit it. |
| P4 | Output layout | Folder numbers don't match code step numbers: deepTools is "Step 06" in code but publishes to `08_deeptools`; HOMER is 07; BAM stats is `06_bam_stats`. |
| P5 | `conf/modules.config:107` | `ext.args2 = ''` for `HOMER_TAG_DIR` does nothing; the module only reads `ext.args`. |

---

## 4. CUT&RUN methodology & tool parameters

| Step | Current | Assessment / recommendation |
|------|---------|-----------------------------|
| **Trimmomatic** (`nextflow.config:49-51`) | `ILLUMINACLIP:TruSeq3-PE-2.fa:2:25:7:1:true SLIDINGWINDOW:4:10 TRAILING:3 MINLEN:10` | `minAdapterLength=1` with palindrome mode is very aggressive; it's defensible for CUT&RUN's short fragments, but document why. **`MINLEN:10` is too permissive:** 10-mers map to many loci even in a ~100 Mb genome. That wastes Bowtie2 time and leans entirely on the MAPQ filter. Use MINLEN 20–25. For reference, CUT&RUNTools uses `2:15:4:4:true LEADING:20 TRAILING:20 SLIDINGWINDOW:4:15 MINLEN:25`. |
| **Bowtie2** (`nextflow.config:54`) | `--very-sensitive -N 0 -X 500` (end-to-end) | Missing `--no-mixed --no-discordant`, so unpaired and discordant alignments go into dedup and coverage. Add `--dovetail` (common in CUT&RUN where mates overlap after trimming) and `-I 10`. **`-X 500` drops longer di-nucleosomal fragments;** the Henikoff protocol uses `-X 700`. Consider `--no-unal`. Pipe output to `samtools` to write BAM instead of SAM. |
| **Picard** | SortSam → MarkDuplicates `REMOVE_DUPLICATES=true` | In CUT&RUN, MNase cutting bias produces many *genuine* identical fragments at high-occupancy sites, especially for abundant histone marks. nf-core/cutandrun only marks duplicates in target samples by default and removes them only in IgG controls. Make removal configurable per target/control (`meta.control_id` already exists). MultiQC names the Picard sample `<id>_sort` (from the INPUT header), which doesn't match the other tools' `<id>`. |
| **MAPQ filter** (`samtools/main.nf:24-28`) | `samtools view -h -q 10` | Filters on MAPQ only, with no `-f 2 -F 0x904`/`1804`. When one mate passes and the other doesn't, an **orphan read** is left behind, which breaks fragment-based coverage. MAPQ 10 in Bowtie2's scale is lenient; ≥ 20–30 is more usual for histone and TF CUT&RUN. Output is SAM, then converted back to BAM in deepTools (BAM→SAM→BAM). |
| **deepTools bamCoverage** | `--normalizeUsing RPKM --binSize 10` | **No `--extendReads`/`-e`:** it counts read ends, not paired fragments. For CUT&RUN, use fragment coverage (`-e`, optionally `--centerReads`). No `--blackListFileName`; ce11 has published blacklists (Amemiya et al. 2019). RPKM with 10 bp bins is the same as CPM up to a constant, so CPM is clearer. |
| **Spike-in** | None | No E. coli carry-over or exogenous spike-in alignment or scaling. Spike-in calibration is the standard CUT&RUN way to compare conditions with global changes (e.g. H3K27me3 knockdowns). It's a major gap if this pipeline feeds differential analysis. |
| **HOMER makeTagDirectory** | Default options on paired SAM | HOMER counts each mate as a separate tag and estimates fragment length. Consider `-format sam` explicitly, and decide on `-tbp`. Document that it treats each mate as a single-end tag. |
| **HOMER makeUCSCfile → bedGraphToBigWig** | default `-norm 1e7`, fragLength auto | HOMER can extend fragments past chromosome ends, which makes `bedGraphToBigWig` fail ("end coordinate past chromosome end"). Pipe through `bedClip`. Use `LC_ALL=C sort` instead of `LC_COLLATE` (`ucsc_bw/main.nf:32`). The pipeline produces **two BigWigs with different normalizations** (HOMER 10M-tag vs deepTools RPKM). Commit `9f449a0` gave both the same filename `${prefix}.bw`, so once downloaded they're indistinguishable. Restore a distinguishing suffix such as `.homer.bw` / `.rpkm.bw`. |
| **QC** | FastQC raw/trimmed, Trimmomatic, Bowtie2, Picard, samtools stats | Good base. Missing: a fragment-size histogram (the key CUT&RUN check for nucleosomal periodicity), FRiP and fingerprint plots (could be downstream). FastQC sample names (`<id>_R1_001`) won't merge with the other tools' `<id>` in General Stats; add `extra_fn_clean_exts` for `_R1_001`/`_R2_001`. |

---

## 5. Concrete bugs, edge cases & prioritized recommendations

### 🔴 Critical

**B1. The example config silently disables most steps.** `docs/Example_Run/config/experiment.config:29-31` sets `run_index_bam`, `run_homer_ucsc` and `run_ucsc_bigwig`, which no longer exist. The current toggles (`run_deeptools_bam_bw`, `run_bam_stats`, `run_homer_tag_dir`, `run_homer_ucsc_bw`, `run_multiqc_all`) default to `false` (`nextflow.config:21-32`), so the reference run stops after MAPQ filtering and still reports success. Update the example; a params schema or typed `params {}` block would reject unknown keys.

**B2. Bowtie2 ignores its staged index.** `modules/local/bowtie2/main.nf:29` uses `-x "${params.bowtie2_index}"` instead of the staged `index` input (line 12). This:
- breaks Docker, because `/share/...` isn't mounted;
- breaks cloud and Seqera Platform executors;
- means `-resume` doesn't track index changes.

Derive the prefix from the staged files instead:
```bash
INDEX=$(find -L ./ -name "*.rev.1.bt2" | sed 's/\.rev\.1\.bt2$//')
```

**B3. The samplesheet is mandatory, though documented as optional.** `lib/utils.nf:10-16` returns an empty map when the samplesheet is missing, and `buildMeta` (`lib/utils.nf:53-55`) then errors for every sample. README lines 148, 190 and 239 say IDs are inferred when the samplesheet is missing. Either fall back to `[id: sample_id, single_end: false]` or make the samplesheet required and validated.

### 🟠 Major

**B4. Dropbox staging can race publishDir.** `workflows/cutandrun_base.nf:283-305`: the barrier waits for upstream *channel emissions*. Nextflow publishes files asynchronously, so `RCLONE_STAGE_DROPBOX` can start while large files are still being copied. Run the sync in an `onComplete:` handler or as a post-run script.

**B5. rclone filters probably skip flat directories.** `bin/stage_results_dropbox.sh:49,52`: `--include "**/*"` likely doesn't match top-level files. The latest commit added `"*.html"` for `02_multiqc` (line 45), which suggests this already happened. `06_bam_stats/` and `pipeline_info/` are flat, so they may never be uploaded. Use `--include "**"` or drop the filter. Lines 45–46 are redundant once fixed.

**B6. A relative `outdir` breaks rclone.** `RCLONE_STAGE_DROPBOX` runs in the task work directory with `outdir` passed as a `val`. A relative `params.outdir` fails with "Results directory not found". Resolve it with `file(params.outdir).toAbsolutePath()`.

**B7. Process-substitution logging can race.** `bowtie2/main.nf:32` and `trimmomatic/main.nf:59` use `2> >(tee log >&2)`. Bash doesn't wait for the substituted `tee`, so the log can be truncated when the task ends. Bowtie2 writes its summary last, so this breaks MultiQC parsing intermittently. Use `2> log` then `cat log >&2`.

**B8. Missing chrom sizes fail late.** `lib/utils.nf:72-78` returns `[]` when chrom sizes are missing, so `HOMER_UCSC_BW` fails late and cryptically. Error up front when `run_homer_ucsc_bw` is on.

**B9. Fallback channels can abort valid runs** (A4): stale outputs in `outdir` trigger `buildMeta` errors or `.bai` `checkIfExists` failures.

**B10. Inputs are never checked** (A7): empty upstream channels give silent no-op runs.

**B11. Retry strategy** (R1, R2): no resource escalation and no wall-time control on LSF.

**B12. Version mismatch and outdated tools** (C1, C2): samtools 1.21 vs 1.25 between conda and container; Picard 2.5.0.

**B13. Paired-end handling** (section 4): no `--no-mixed --no-discordant`, no `-f 2` filtering, and no `--extendReads`. Coverage tracks are read-based and can include orphan mates.

**B14. Unconditional duplicate removal** for every target (section 4).

**B15. `includeConfig "${launchDir}/config/experiment.config"`** (C10) prevents launching from anywhere else, including Seqera Platform.

### 🟡 Minor

- **B16:** HOMER and deepTools BigWigs share the name `${prefix}.bw` (`homer/ucsc_bw/main.nf:15`).
- **B17:** `MINLEN:10` (`nextflow.config:51`) and Bowtie2 `-X 500` (`nextflow.config:54`).
- **B18:** SAM intermediates are published (P1); BAM→SAM→BAM round trip (`samtools/main.nf`, `deeptools/main.nf:32`).
- **B19:** `gocryptfs` in the HOMER env, the bloated HOMER container, and hard-coded HOMER/UCSC versions (C3–C5).
- **B20:** The single `\` continuation at `homer/ucsc_bw/main.nf:29` is inconsistent with the `\\` style elsewhere. It works only because Groovy treats it as a line continuation.
- **B21:** `software_mqc_versions.yml` isn't fed to MultiQC (A15); sample names don't line up across FastQC and Picard in MultiQC.
- **B22:** Deprecated `when:` blocks (A1), unused imports (A2), `onComplete` assignment style (A3), and dead `ch_existing_bedgraph` (A5).
- **B23:** String CPUs/memory in `conf/base.config`; no `resourceLimits`; over-allocated labels for Picard and HOMER (R4, R6).
- **B24:** Invalid relative Docker mount (R7); no conda profile; no `singularity.cacheDir` (C9).
- **B25:** `manifest.homePage` is wrong (C11); `params.outdir` has no default; `help` and `email` are unused (A12).
- **B26:** Leftover `test.nf`; no nf-test or CI; nested `samtools/stats` module layout (A10, A16).
- **B27:** The MultiQC fallback globs (`main.nf:92-97`) pick up historical logs for samples outside the current run.
- **B28 (low confidence):** The `configProcessNamesValidation` ordering may override the `debug` profile (R8).

### Suggested order of work
1. Fix B1–B3 and add input checks (B8, B10).
2. Switch Bowtie2 to the staged index, fix the logging race, and change paired-end alignment and filtering to `--no-mixed --no-discordant` plus `-f 2 -F 1804` (B2, B7, B13).
3. Rework Dropbox staging to run after the run completes, with corrected filters and an absolute path (B4–B6).
4. Add resource escalation, time limits, `resourceLimits` and LSF `executor {}` settings (B11).
5. Align container and conda versions and upgrade Picard, ideally by moving to nf-core modules (B12, A11).
6. Settle methodology: fragment-based CPM or spike-in scaling, a blacklist, configurable dedup, and distinct BigWig names (B14, B16).
