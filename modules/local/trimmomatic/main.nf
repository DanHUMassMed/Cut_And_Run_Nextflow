process TRIMMOMATIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/trimmomatic:0.39--hdfd78af_2'
        : 'quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2'}"

    input:
    tuple val(meta), path(reads)
    path adapters

    output:
    tuple val(meta), path("*_paired.fq.gz")   , emit: paired_reads
    tuple val("${task.process}"), val('trimmomatic'), eval("trimmomatic -version 2>/dev/null || echo '0.39'"), emit: versions_trimmomatic, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def illuminaclip = task.ext.args2 ?: "${params.trimmomatic_illuminaclip ?: '2:25:7:1:true'}"
    def args = task.ext.args ?: "${params.trimmomatic_args ?: 'SLIDINGWINDOW:4:10 TRAILING:3 MINLEN:10'}"
    """
    R1="${reads[0]}"
    R2="${reads[1]}"

    BASE_R1=\$(basename "\$R1")
    BASE_R1=\${BASE_R1%.fastq.gz}
    BASE_R1=\${BASE_R1%.fq.gz}

    BASE_R2=\$(basename "\$R2")
    BASE_R2=\${BASE_R2%.fastq.gz}
    BASE_R2=\${BASE_R2%.fq.gz}

    OUT_R1_P="\${BASE_R1}_paired.fq.gz"
    OUT_R1_U="\${BASE_R1}_unpaired.fq.gz"
    OUT_R2_P="\${BASE_R2}_paired.fq.gz"
    OUT_R2_U="\${BASE_R2}_unpaired.fq.gz"

    ADAPTERS="${adapters}"
    if [[ ! -f "\$ADAPTERS" ]]; then
        ADAPTERS=\$(find /usr/local/share /opt/conda/share -name "TruSeq3-PE-2.fa" 2>/dev/null | head -n 1 || true)
    fi
    if [[ -z "\$ADAPTERS" || ! -f "\$ADAPTERS" ]]; then
        echo "ERROR: Trimmomatic adapters file not found: ${adapters}" >&2
        exit 1
    fi

    trimmomatic PE \\
        -threads ${task.cpus} \\
        "\$R1" "\$R2" \\
        "\$OUT_R1_P" "\$OUT_R1_U" \\
        "\$OUT_R2_P" "\$OUT_R2_U" \\
        ILLUMINACLIP:"\$ADAPTERS":${illuminaclip} \\
        ${args} \\
        2> >(tee "${prefix}_trimmomatic.log" >&2)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    R1="${reads[0]}"
    R2="${reads[1]}"

    BASE_R1=\$(basename "\$R1")
    BASE_R1=\${BASE_R1%.fastq.gz}
    BASE_R1=\${BASE_R1%.fq.gz}

    BASE_R2=\$(basename "\$R2")
    BASE_R2=\${BASE_R2%.fastq.gz}
    BASE_R2=\${BASE_R2%.fq.gz}

    echo "" | gzip > "\${BASE_R1}_paired.fq.gz"
    echo "" | gzip > "\${BASE_R1}_unpaired.fq.gz"
    echo "" | gzip > "\${BASE_R2}_paired.fq.gz"
    echo "" | gzip > "\${BASE_R2}_unpaired.fq.gz"
    touch "${prefix}_trimmomatic.log"
    """
}

