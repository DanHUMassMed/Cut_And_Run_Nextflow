process BOWTIE2_ALIGN {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/d4/d4990a9e13c1aad32d60f19e0ced204f2f1e231fe856290ce75713505a1bfe44/data'
        : 'community.wave.seqera.io/library/bowtie2_htslib_samtools_pigz:dbd18842ad7cb278'}"

    input:
    tuple val(meta), path(reads)
    tuple val(index_meta), path(index)

    output:
    tuple val(meta), path("${prefix}_bowtieoutput.sam"), emit: sam
    tuple val(meta), path("${prefix}_bowtie2.log")     , emit: log
    tuple val("${task.process}"), val('bowtie2'), eval("(bowtie2 --version 2>&1 || true) | sed -n 's/.*bowtie2-align-s version //p'"), emit: versions_bowtie2, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: "${params.bowtie2_args ?: '--very-sensitive -N 0 -X 500'}"
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    INDEX=\$(find -L ./ -name "*.rev.1.bt2*" | head -n 1 | sed -E 's/\\.rev\\.1\\.bt2l?\$//')
    if [[ -z "\$INDEX" ]]; then
        INDEX="${params.bowtie2_index}"
    fi

    bowtie2 -q \\
        ${args} \\
        -p ${task.cpus} \\
        -x "\$INDEX" \\
        -1 "${reads[0]}" -2 "${reads[1]}" \\
        -S "${prefix}_bowtieoutput.sam" \\
        2> >(tee "${prefix}_bowtie2.log" >&2)
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}_bowtieoutput.sam"
    touch "${prefix}_bowtie2.log"
    """
}

