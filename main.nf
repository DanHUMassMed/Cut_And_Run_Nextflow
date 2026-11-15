#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CUT&RUN Upstream Base Pipeline (HPC)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CUTANDRUN_BASE } from './workflows/cutandrun_base'
include {
    loadSamplesheetMap;
    extractSampleId;
    buildMeta;
    resolveBowtie2Index;
    resolveChromSizes;
    resolvePairedFastq;
    resolveInputFiles;
} from './lib/utils'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW Entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    if (!params.experiment || !params.fastq_dir || !params.outdir) {
        error("params.experiment, params.fastq_dir, and params.outdir must be set in config/experiment.config.")
    }


    log.info """\
    ========================================================================
     C U T & R U N   U P S T R E A M   B A S E   P I P E L I N E
    ========================================================================
     experiment                 : ${params.experiment}
     fastq_dir                  : ${params.fastq_dir}
     input_fastq                : ${params.input_fastq}
     outdir                     : ${params.outdir}
     samplesheet                : ${params.samplesheet}
     bowtie2_index              : ${params.bowtie2_index}
     chrom_sizes                : ${params.chrom_sizes}
     ----------------------------------------------------------------------
     Active Step Toggles:
       fastqc_raw               : ${params.run_raw_fastqc}
       trimmomatic              : ${params.run_trimmomatic}
       fastqc_trimmed           : ${params.run_trimmed_fastqc}
       bowtie2_align            : ${params.run_bowtie2_align}
       picard_dedup             : ${params.run_picard_dedup}
       samtools_mapq_filter     : ${params.run_mapq_filter}
       deeptools_bam_bw         : ${params.run_deeptools_bam_bw}
       homer_tagdir             : ${params.run_homer_tag_dir}
       homer_ucsc_ucsc          : ${params.run_homer_ucsc_bw}
    ========================================================================
    """.stripIndent()

    def input_align_sam = "${params.outdir}/03_align/*_align.sam"
    def input_dedup_bam = "${params.outdir}/04_dedup/*_dedup.bam"
    def input_mapq_sam  = "${params.outdir}/05_mapq_filter/*_mapqfilter.sam"
    def input_bedgraph  = "${params.outdir}/07_homer/ucsc_bw/*.ucsc.bedGraph.gz"

    //
    // Load optional sample metadata from samplesheet.csv if present
    //
    def samplesheet_map = loadSamplesheetMap(params.samplesheet)

    //
    // Resolve reference files for alignment and BigWig conversion
    //
    def ch_bowtie2_index       = resolveBowtie2Index(params.bowtie2_index)
    def ch_chrom_sizes         = resolveChromSizes(params.chrom_sizes)

    def ch_raw_reads           = resolvePairedFastq(params.input_fastq, samplesheet_map)
    def ch_existing_trimmed    = resolvePairedFastq(params.input_trimmed_fastq, samplesheet_map, ['.paired.trim', '_paired'])

    def ch_existing_align_sam  = resolveInputFiles(input_align_sam, samplesheet_map, ['_align.sam'])
    def ch_existing_dedup_bam  = resolveInputFiles(input_dedup_bam, samplesheet_map, ['_dedup.bam', '.bam'])
    def ch_existing_mapq_sam   = resolveInputFiles(input_mapq_sam, samplesheet_map, ['_mapqfilter.sam', '.sam'])
    def ch_existing_bedgraph   = resolveInputFiles(input_bedgraph, samplesheet_map, ['.ucsc.bedGraph.gz', '.bedGraph.gz', '.bedGraph'])
    //
    // WORKFLOW: Run CUTANDRUN_BASE
    //
    CUTANDRUN_BASE(
        ch_raw_reads,
        ch_existing_trimmed,
        ch_existing_align_sam,
        ch_existing_dedup_bam,
        ch_existing_mapq_sam,
        ch_existing_bedgraph,
        ch_bowtie2_index,
        ch_chrom_sizes
    )

    workflow.onComplete = {
        if (workflow.success) {
            log.info "\nUpstream base pipeline completed successfully! Results available in: ${params.outdir}\n"
        } else {
            log.warn "\nUpstream base pipeline completed with errors. Check the logs for details.\n"
        }
    }
}
