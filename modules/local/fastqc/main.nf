process FASTQC {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/fastqc:0.12.1--hdfd78af_0'
        : 'quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*_fastqc.html"), emit: html
    tuple val(meta), path("*_fastqc.zip") , emit: zip
    tuple val("${task.process}"), val('fastqc'), eval('(fastqc --version || true) | sed "/FastQC v/!d; s/.*v//"'), emit: versions_fastqc, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    fastqc \\
        --threads ${task.cpus} \\
        ${args} \\
        -o . \\
        ${reads}
    """

    stub:
    """
    for fq in ${reads}; do
        base=\$(basename "\$fq")
        base=\${base%.fastq.gz}
        base=\${base%.fq.gz}
        touch "\${base}_fastqc.html"
        touch "\${base}_fastqc.zip"
    done
    """
}

