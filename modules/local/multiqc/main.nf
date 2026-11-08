process MULTIQC {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c8/c8e346f4f6080eadf1253505e6ff09ef004454fc18e8d672006fd7b222cc412e/data'
        : 'community.wave.seqera.io/library/multiqc:1.35--c17fb751507e9dfc'}"

    input:
    tuple val(meta), path(multiqc_files, stageAs: "?/*")

    output:
    tuple val(meta), path("*.html") , emit: report
    tuple val(meta), path("*_data") , emit: data
    tuple val(meta), path("*_plots"), emit: plots, optional: true
    tuple val("${task.process}"), val('multiqc'), eval('(multiqc --version || true) | sed "s/.* //g"'), emit: versions_multiqc, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    multiqc \\
        --force \\
        --filename ${prefix}.html \\
        ${args} \\
        .
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p ${prefix}_data
    touch ${prefix}_data/.stub
    touch ${prefix}.html
    """
}

