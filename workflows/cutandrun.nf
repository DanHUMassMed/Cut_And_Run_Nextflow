/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC as FASTQC_ORIGINAL   } from '../modules/nf-core/fastqc/main'
include { MULTIQC as MULTIQC_ORIGINAL } from '../modules/nf-core/multiqc/main'
include { TRIMMOMATIC                 } from '../modules/nf-core/trimmomatic/main'
include { FASTQC as FASTQC_TRIMMED    } from '../modules/nf-core/fastqc/main'
include { MULTIQC as MULTIQC_TRIMMED  } from '../modules/nf-core/multiqc/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CUTANDRUN {

    take:
    ch_reads        // channel: [ val(meta), [ path(reads_1), path(reads_2) ] ]
    multiqc_config  // val: optional path to custom multiqc config
    multiqc_logo    // val: optional path to custom multiqc logo

    main:
    def default_mqc_config = file("${projectDir}/assets/multiqc_config.yml")
    def mqc_config_file = multiqc_config
        ? file(multiqc_config, checkIfExists: true)
        : (default_mqc_config.exists() ? default_mqc_config : [])
    def mqc_logo_file = multiqc_logo
        ? file(multiqc_logo, checkIfExists: true)
        : []

    //
    // MODULE: Run FastQC on original (untrimmed) reads
    //
    FASTQC_ORIGINAL(ch_reads)

    //
    // MODULE: Run Trimmomatic on original paired-end reads
    //
    TRIMMOMATIC(ch_reads)

    //
    // MODULE: Run FastQC on trimmed paired-end reads
    //
    FASTQC_TRIMMED(TRIMMOMATIC.out.trimmed_reads)

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

    //
    // MODULE: Run MultiQC for original reads
    //
    def ch_multiqc_original_files = FASTQC_ORIGINAL.out.zip
        .map { _meta, zip -> zip }
        .mix(ch_collated_versions)

    def ch_multiqc_original_input = ch_multiqc_original_files
        .flatten()
        .collect()
        .map { files ->
            [
                [ id: 'original' ],
                files,
                mqc_config_file,
                mqc_logo_file,
                [],
                []
            ]
        }

    MULTIQC_ORIGINAL(ch_multiqc_original_input)

    //
    // MODULE: Run MultiQC for trimmed reads (including Trimmomatic logs)
    //
    def ch_multiqc_trimmed_files = FASTQC_TRIMMED.out.zip
        .map { _meta, zip -> zip }
        .mix(TRIMMOMATIC.out.out_log.map { _meta, log_file -> log_file })
        .mix(ch_collated_versions)

    def ch_multiqc_trimmed_input = ch_multiqc_trimmed_files
        .flatten()
        .collect()
        .map { files ->
            [
                [ id: 'trimmed' ],
                files,
                mqc_config_file,
                mqc_logo_file,
                [],
                []
            ]
        }

    MULTIQC_TRIMMED(ch_multiqc_trimmed_input)

    emit:
    fastqc_original_html   = FASTQC_ORIGINAL.out.html
    fastqc_original_zip    = FASTQC_ORIGINAL.out.zip
    trimmed_reads          = TRIMMOMATIC.out.trimmed_reads
    unpaired_reads         = TRIMMOMATIC.out.unpaired_reads
    trimmomatic_out_log    = TRIMMOMATIC.out.out_log
    trimmomatic_summary    = TRIMMOMATIC.out.summary
    fastqc_trimmed_html    = FASTQC_TRIMMED.out.html
    fastqc_trimmed_zip     = FASTQC_TRIMMED.out.zip
    multiqc_original_report = MULTIQC_ORIGINAL.out.report
    multiqc_trimmed_report  = MULTIQC_TRIMMED.out.report
    versions               = ch_collated_versions
}
