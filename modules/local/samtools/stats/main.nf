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
