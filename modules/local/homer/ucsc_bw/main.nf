process HOMER_UCSC_BW {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/a0/a0dbdca6215b94a40619b41df291e56e9dbabc0db0219fe2faec4f207e588863/data'
        : 'community.wave.seqera.io/library/homer_ucsc-bedgraphtobigwig_gzip_gocryptfs:1eb99b08887c59ea'}"

    input:
    tuple val(meta), path(tag_dir)
    path chrom_sizes

    output:
    tuple val(meta), path("${prefix}.bw")         , emit: bigwig
    tuple val(meta), path("${prefix}.ucsc.bedGraph.gz") , emit: bedgraph, optional: true
    tuple val("${task.process}"), val('homer'), val('4.11'), emit: versions_homer, topic: versions
    tuple val("${task.process}"), val('ucsc'), val('482')  , emit: versions_ucsc, topic: versions


    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    makeUCSCfile "${tag_dir}" -o "${prefix}.ucsc.bedGraph" ${args}
    gzip -dc "${prefix}.ucsc.bedGraph.gz" \
        | grep -v '^#' \
        | grep -v '^track' \
        | LC_COLLATE=C sort -k1,1 -k2,2n \
        > "${prefix}.temp.bedGraph"

    
    bedGraphToBigWig \\
        ${args2} \\
        "${prefix}.temp.bedGraph" \\
        "${chrom_sizes}" \\
        "${prefix}.bw"

    rm -f "${prefix}.temp.bedGraph"
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > "${prefix}.ucsc.bedGraph.gz"
    touch "${prefix}.bw"
    """
}

