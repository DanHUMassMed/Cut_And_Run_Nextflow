process PICARD_DEDUP {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/b4/b474c6f12c0502377b95062b75ef4b7778864b1353c7fc1d5a3b1f3b3017fd2e/data'
        : 'community.wave.seqera.io/library/picard:3.5.0--be20f299a1924f0d'}"

    input:
    tuple val(meta), path(sam)

    output:
    tuple val(meta), path("${prefix}_PicardDedup.bam"), emit: bam
    tuple val(meta), path("${prefix}_dup.txt")        , emit: metrics
    tuple val("${task.process}"), val('picard'), eval("(picard MarkDuplicates --version 2>&1 || true) | sed -n 's/.*Version://p' | head -n 1"), emit: versions_picard, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def stringency = params.picard_validation_stringency ?: 'LENIENT'
    def remove_dups = params.picard_remove_duplicates != null ? params.picard_remove_duplicates : true
    def avail_mem = task.memory ? (task.memory.mega * 0.8).intValue() : 4096
    """
    mkdir -p tmp_picard

    picard -Xmx${avail_mem}M SortSam \\
        --INPUT "${sam}" \\
        --OUTPUT "${prefix}_PicardSort.bam" \\
        --VALIDATION_STRINGENCY ${stringency} \\
        --TMP_DIR tmp_picard \\
        --SORT_ORDER coordinate

    picard -Xmx${avail_mem}M MarkDuplicates \\
        --INPUT "${prefix}_PicardSort.bam" \\
        --OUTPUT "${prefix}_PicardDedup.bam" \\
        --VALIDATION_STRINGENCY ${stringency} \\
        --TMP_DIR tmp_picard \\
        --METRICS_FILE "${prefix}_dup.txt" \\
        --REMOVE_DUPLICATES ${remove_dups}

    rm -rf "${prefix}_PicardSort.bam" tmp_picard
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}_PicardDedup.bam"
    touch "${prefix}_dup.txt"
    """
}

