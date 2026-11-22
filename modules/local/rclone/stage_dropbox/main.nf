process RCLONE_STAGE_DROPBOX {
    tag "${params.experiment}"
    label 'process_single'
    cache false

    input:
    val ready_token
    val outdir
    val rclone_remote

    output:
    path "rclone_dropbox_sync.log", emit: log


    script:
    def args = task.ext.args ?: '--transfers 4 --checkers 8 -v'
    """
    stage_results_dropbox.sh \\
        "${outdir}" \\
        "${rclone_remote}" \\
        "rclone_dropbox_sync.log" \\
        ${args}
    """

    stub:
    """
    echo "STUB: Would stage ${outdir} -> ${rclone_remote}" > rclone_dropbox_sync.log
    """
}
