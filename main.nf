#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CUT&RUN FastQC + Trimmomatic + MultiQC Pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CUTANDRUN } from './workflows/cutandrun'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    HELP MESSAGE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def helpMessage() {
    log.info """
    ========================================================================
     CUT&RUN Quality Control & Trimming Pipeline
    ========================================================================
    Usage:
      nextflow -c config/experiment.config run ../

    Options:
      --fastq                     Glob pattern for paired-end FASTQ files
                                  (default: ${params.fastq})
      --trimmomatic_adapters      Adapter FASTA file
                                  (default: ${params.trimmomatic_adapters})
      --trimmomatic_illuminaclip  ILLUMINACLIP parameters
                                  (default: ${params.trimmomatic_illuminaclip})
      --trimmomatic_slidingwindow SLIDINGWINDOW parameters
                                  (default: ${params.trimmomatic_slidingwindow})
      --trimmomatic_trailing      TRAILING quality threshold
                                  (default: ${params.trimmomatic_trailing})
      --trimmomatic_minlen        MINLEN minimum read length
                                  (default: ${params.trimmomatic_minlen})
      --outdir                    Output directory for results
                                  (default: ${params.outdir})
      --multiqc_title             Optional custom title for MultiQC reports
      --multiqc_config            Optional custom MultiQC configuration file
      --multiqc_logo              Optional custom logo for MultiQC reports
    ========================================================================
    """.stripIndent()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW Entrypoint
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    if (params.help) {
        helpMessage()
        exit 0
    }

    log.info """\
    ========================================================================
     C U T & R U N   P I P E L I N E
    ========================================================================
     experiment   : ${params.experiment}
     fastq        : ${params.fastq}
     adapters     : ${params.trimmomatic_adapters}
     illuminaclip : ${params.trimmomatic_illuminaclip}
     slidingwin   : ${params.trimmomatic_slidingwindow}
     trailing     : ${params.trimmomatic_trailing}
     minlen       : ${params.trimmomatic_minlen}
     outdir       : ${params.outdir}
    ========================================================================
    """.stripIndent()

    //
    // Build input channel of [ val(meta), [ path(reads_1), path(reads_2) ] ]
    //
    def ch_reads = channel
        .fromFilePairs(params.fastq, checkIfExists: true)
        .map { sample_id, reads ->
            [ [ id: sample_id, single_end: false ], reads ]
        }

    //
    // WORKFLOW: Run CUTANDRUN (FastQC -> Trimmomatic -> FastQC -> MultiQC)
    //
    CUTANDRUN(
        ch_reads,
        params.multiqc_config,
        params.multiqc_logo
    )

    onComplete:
    if (workflow.success) {
        log.info """
        Done! Reports available in:
          - Original MultiQC : ${params.outdir}/multiqc/multiqc_original_report.html
          - Trimmed MultiQC  : ${params.outdir}/multiqc/multiqc_trimmed_report.html
        """.stripIndent()
    } else {
        log.warn "\nPipeline execution completed with errors. Check the logs for details.\n"
    }
}
