nextflow.enable.dsl = 2

params.fastq_dir   = "${launchDir}/data/fastq"
params.fastq_glob  = "${params.fastq_dir}/*_R{1,2}_*.f*q.gz"
params.samplesheet = "${launchDir}/config/samplesheet.csv"

def loadSamplesheetMap(samplesheet_path) {
    def meta_map = [:]
    if (!samplesheet_path) {
        return meta_map
    }
    def sheet_file = file(samplesheet_path)
    if (!sheet_file.exists()) {
        return meta_map
    }
    sheet_file.splitCsv(header: true, strip: true).each { row ->
        if (row.sample_id) {
            meta_map[row.sample_id] = [
                id         : row.sample_id,
                single_end : false,
                sample_name: row.sample_name ?: row.sample_id,
                condition  : row.condition ?: (row.sample_name ?: 'default'),
                target     : row.target ?: 'default',
                replicate  : row.replicate ? row.replicate.toInteger() : 1,
                control_id : row.control_id ?: null
            ]
        }
    }
    return meta_map
}
/*
 * Extracts the sample ID by removing a matching suffix, 
 * falling back to the filename without its extension.
 */
def extractSampleId(input, suffixes = []) {
    def name = input instanceof Path
        ? input.getName()
        : input.toString()

    def matched_suffix = suffixes.find { suffix -> name.endsWith(suffix) }

    if (matched_suffix) {
        return name.substring(0, name.length() - matched_suffix.length())
    }

    return input instanceof Path
        ? input.getBaseName()
        : name
}


def buildMeta(sample_id, samplesheet_map) {
    if (!samplesheet_map.containsKey(sample_id)) {
        error "Sample ID '${sample_id}' not found in samplesheet. Available IDs: ${samplesheet_map.keySet().sort().join(', ')}"
    }

    return samplesheet_map[sample_id]
}

def resolveBowtie2Index(index_param) {
    def bt2_files = files("${index_param}*.bt2*")

    if (!bt2_files) {
        error "No Bowtie2 index files found for prefix: ${index_param}"
    }

    return [
        [ id: file(index_param).name ],
        bt2_files
    ]
}
def resolveChromSizes(chrom_sizes_param) {
    if (!chrom_sizes_param) {
        return []
    }
    def cs_file = file(chrom_sizes_param)
    return cs_file.exists() ? cs_file : []
}


workflow {
    def samplesheet_map = loadSamplesheetMap(params.samplesheet)
    channel
        .fromFilePairs(params.fastq_glob, checkIfExists: true)
        .view { pair_id, reads -> "DISCOVERED: ${pair_id} -> ${reads*.name}" }
        .map { pair_id, reads ->
            def sample_id = extractSampleId(pair_id, ['.paired.trim', '_paired'])
            [buildMeta(sample_id, samplesheet_map), reads]
        }
        .view { meta, reads -> "OUTPUT: ${meta.id} -> ${reads*.name}" }
}