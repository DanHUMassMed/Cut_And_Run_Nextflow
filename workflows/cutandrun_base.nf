/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC as FASTQC_RAW       } from '../modules/local/fastqc/main'
include { MULTIQC as MULTIQC_RAW     } from '../modules/local/multiqc/main'
include { TRIMMOMATIC                } from '../modules/local/trimmomatic/main'
include { FASTQC as FASTQC_TRIMMED   } from '../modules/local/fastqc/main'
include { MULTIQC as MULTIQC_TRIMMED } from '../modules/local/multiqc/main'
include { BOWTIE2_ALIGN              } from '../modules/local/bowtie2/main'
include { PICARD_DEDUP               } from '../modules/local/picard/main'
include { SAMTOOLS_MAPQ_FILTER       } from '../modules/local/samtools/main'
include { DEEPTOOLS_BAM_BW           } from '../modules/local/deeptools/main'
include { HOMER_TAG_DIR              } from '../modules/local/homer/tag_dir/main'
include { HOMER_UCSC_BW              } from '../modules/local/homer/ucsc_bw/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CUTANDRUN_BASE {

    take:
    ch_raw_reads             // channel: [ val(meta), [ path(r1), path(r2) ] ]
    ch_existing_trimmed      // channel: [ val(meta), [ path(r1), path(r2) ] ]
    ch_existing_align_sam    // channel: [ val(meta), path(sam) ]
    ch_existing_dedup_bam    // channel: [ val(meta), path(bam) ]
    ch_existing_mapq_sam     // channel: [ val(meta), path(sam) ]
    ch_existing_bedgraph     // channel: [ val(meta), path(bedgraph) ]
    ch_bowtie2_index         // value:   [ val(meta2), path(index_files) ]
    ch_chrom_sizes           // value:   path(chrom_sizes)

    main:

    //
    // Step 00: Raw Read QC (FastQC + MultiQC on incoming raw FASTQ pairs)
    //
    def ch_raw_fastqc_html = channel.empty()
    def ch_raw_fastqc_zip  = channel.empty()
    def ch_raw_multiqc     = channel.empty()

    if (params.run_raw_fastqc) {
        FASTQC_RAW(ch_raw_reads)
        ch_raw_fastqc_html = FASTQC_RAW.out.html
        ch_raw_fastqc_zip  = FASTQC_RAW.out.zip

        def ch_raw_multiqc_in = ch_raw_fastqc_zip
            .map { _meta, zips -> zips }
            .flatten()
            .collect()
            .map { files -> [ [ id: 'multiqc_original_report' ], files ] }

        MULTIQC_RAW(ch_raw_multiqc_in)
        ch_raw_multiqc = MULTIQC_RAW.out.report
    }

    //
    // Step 01: Adapter Trimming with Trimmomatic PE
    //
    def ch_trimmed_reads = ch_existing_trimmed

    if (params.run_trimmomatic) {
        TRIMMOMATIC(
            ch_raw_reads,
            file(params.trimmomatic_adapters, checkIfExists: true)
        )
        ch_trimmed_reads = TRIMMOMATIC.out.paired_reads
    }

    //
    // Step 02: Trimmed Read QC (FastQC + MultiQC on trimmed paired FASTQ outputs)
    //
    def ch_trimmed_fastqc_html = channel.empty()
    def ch_trimmed_fastqc_zip  = channel.empty()
    def ch_trimmed_multiqc     = channel.empty()

    if (params.run_trimmed_fastqc) {
        FASTQC_TRIMMED(ch_trimmed_reads)
        ch_trimmed_fastqc_html = FASTQC_TRIMMED.out.html
        ch_trimmed_fastqc_zip  = FASTQC_TRIMMED.out.zip

        def ch_trimmed_multiqc_in = ch_trimmed_fastqc_zip
            .map { _meta, zips -> zips }
            .flatten()
            .collect()
            .map { files -> [ [ id: 'multiqc_trimmed_report' ], files ] }

        MULTIQC_TRIMMED(ch_trimmed_multiqc_in)
        ch_trimmed_multiqc = MULTIQC_TRIMMED.out.report
    }

    //
    // Step 03: Paired-End Genome Alignment with Bowtie2 (on trimmed paired reads)
    //
    def ch_align_sam = ch_existing_align_sam

    if (params.run_bowtie2_align) {
        BOWTIE2_ALIGN(
            ch_trimmed_reads,
            ch_bowtie2_index
        )
        ch_align_sam = BOWTIE2_ALIGN.out.sam
    }

    //
    // Step 04: Coordinate Sorting & Duplicate Removal with Picard
    //
    def ch_dedup_bam     = ch_existing_dedup_bam
    def ch_dedup_metrics = channel.empty()

    if (params.run_picard_dedup) {
        PICARD_DEDUP(ch_align_sam)
        ch_dedup_bam     = PICARD_DEDUP.out.bam
        ch_dedup_metrics = PICARD_DEDUP.out.metrics
    }

    //
    // Step 05: Low-Quality Read Filtering (MAPQ >= params.mapq_threshold) with samtools
    //
    def ch_mapq_sam = ch_existing_mapq_sam

    if (params.run_mapq_filter) {
        SAMTOOLS_MAPQ_FILTER(ch_dedup_bam)
        ch_mapq_sam = SAMTOOLS_MAPQ_FILTER.out.sam
    }

    //
    // Step 06: SAM-to-BAM Conversion, Indexing, & deepTools RPKM BigWig
    //
    def ch_bam_bai = channel.empty()
    def ch_rpkm_bw = channel.empty()

    if (params.run_deeptools_bam_bw) {
        DEEPTOOLS_BAM_BW(ch_mapq_sam)
        ch_bam_bai = DEEPTOOLS_BAM_BW.out.bam_bai
        ch_rpkm_bw = DEEPTOOLS_BAM_BW.out.bigwig
    }

    //
    // Step 07: HOMER Tag Directory
    //
    def ch_tagdir = channel.empty()

    if (params.run_homer_tag_dir) {
        HOMER_TAG_DIR(ch_mapq_sam)
        ch_tagdir = HOMER_TAG_DIR.out.tagdir
    }

    //
    // Step 08: HOMER UCSC bedGraph & BigWig Generation
    //
    def ch_ucsc_bw  = channel.empty()
    def ch_bedgraph = ch_existing_bedgraph

    if (params.run_ucsc_bigwig) {
        UCSC_BEDGRAPHTOBIGWIG(
            ch_tagdir,
            ch_chrom_sizes
        )
        ch_ucsc_bw  = UCSC_BEDGRAPHTOBIGWIG.out.bigwig
        ch_bedgraph = UCSC_BEDGRAPHTOBIGWIG.out.bedgraph
    }

    //
    // Collate software versions from Nextflow topic channel
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = topic_versions_string
        .mix(topic_versions.versions_file.map { version_file -> version_file.text })
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'software_mqc_versions.yml',
            sort: true,
            newLine: true
        )

    emit:
    raw_fastqc_html     = ch_raw_fastqc_html
    raw_multiqc         = ch_raw_multiqc
    trimmed_reads       = ch_trimmed_reads
    trimmed_fastqc_html = ch_trimmed_fastqc_html
    trimmed_multiqc     = ch_trimmed_multiqc
    align_sam           = ch_align_sam
    dedup_bam           = ch_dedup_bam
    dedup_metrics       = ch_dedup_metrics
    mapq_sam            = ch_mapq_sam
    bam_bai             = ch_bam_bai
    rpkm_bw             = ch_rpkm_bw
    tagdir              = ch_tagdir
    bedgraph            = ch_bedgraph
    ucsc_bw             = ch_ucsc_bw
    versions            = ch_collated_versions
}
