process HOMER_UCSC_BW {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/21/210205cab907384cc30cfb91fa1eb2d9458021e98debf6d23b90c33d9fb2eb4d/data'
        : 'community.wave.seqera.io/library/ucsc-bedgraphtobigwig:482--2d280d39bedffa30'}"

    input:
    tuple val(meta), path(tag_dir)
    path chrom_sizes

    output:
    tuple val(meta), path("${prefix}.homer.bw")         , emit: bigwig
    tuple val(meta), path("${prefix}.ucsc.bedGraph.gz") , emit: bedgraph, optional: true
    tuple val("${task.process}"), val('homer'), val('4.11'), emit: versions_homer, topic: versions
    tuple val("${task.process}"), val('ucsc'), val('482')  , emit: versions_ucsc, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    makeUCSCfile "${tag_dir}" -o "${prefix}.ucsc.bedGraph.gz" ${args}

    if [[ -f "${prefix}.ucsc.bedGraph.gz" ]]; then
        gzip -dc "${prefix}.ucsc.bedGraph.gz"
    elif [[ -f "${prefix}.ucsc.bedGraph" ]]; then
        cat "${prefix}.ucsc.bedGraph"
    fi | grep -v '^#' | grep -v '^track' | LC_COLLATE=C sort -k1,1 -k2,2n > "${prefix}.temp.bedGraph"
    
    bedGraphToBigWig \\
        ${args2} \\
        "${prefix}.temp.bedGraph" \\
        "${chrom_sizes}" \\
        "${prefix}.homer.bw"

    rm -f "${prefix}.temp.bedGraph"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > "${prefix}.ucsc.bedGraph.gz"
    touch "${prefix}.bw"
    """
}

