
process RECONST_NODDI {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_1.6.0.sif':
        'scilus/scilus:1.6.0' }"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(kernels)

    output:
        tuple val(meta), path("*__FIT_dir.nii.gz")      , emit: dir, optional: true
        tuple val(meta), path("*__FIT_ISOVF.nii.gz")    , emit: isovf, optional: true
        tuple val(meta), path("*__FIT_ICVF.nii.gz")     , emit: icvf, optional: true
        tuple val(meta), path("*__FIT_ECVF.nii.gz")     , emit: ecvf, optional: true
        tuple val(meta), path("*__FIT_OD.nii.gz")       , emit: od, optional: true
        path("kernels")                                 , emit: kernels, optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def para_diff = task.ext.para_diff ? "--para_diff " + task.ext.para_diff : ""
    def iso_diff = task.ext.iso_diff ? "--iso_diff " + task.ext.iso_diff : ""
    def lambda1 = task.ext.lambda1 ? "--lambda1 " + task.ext.lambda1 : ""
    def lambda2 = task.ext.lambda2 ? "--lambda2 " + task.ext.lambda2 : ""
    def nb_threads = task.ext.nb_threads ? "--processes " + task.ext.nb_threads : ""
    def b_thr = task.ext.b_thr ? "--b_thr " + task.ext.b_thr : ""
    def set_kernels = kernels ? "--load_kernels $kernels" : "--save_kernels kernels/ --compute_only"
    def set_mask = mask ? "--mask $mask" : ""

    """
    scil_compute_NODDI.py $dwi $bval $bvec $para_diff $iso_diff $lambda1 \
        $lambda2 $nb_threads $b_thr $set_mask $set_kernels


    if [ -d "$kernels" ]; then
        mv results/FIT_dir.nii.gz ${prefix}__FIT_dir.nii.gz
        mv results/FIT_ICVF.nii.gz ${prefix}__FIT_ICVF.nii.gz
        mv results/FIT_ISOVF.nii.gz ${prefix}__FIT_ISOVF.nii.gz
        mv results/FIT_OD.nii.gz ${prefix}__FIT_OD.nii.gz

        scil_image_math.py subtraction 1 ${prefix}__FIT_ISOVF.nii.gz \
            ${prefix}__FIT_ECVF.nii.gz --exclude_background

        rm -rf results
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: 1.6.0
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_compute_NODDI.py -h
    scil_image_math.py -h
    mkdir kernels
    touch "${prefix}__FIT_dir.nii.gz"
    touch "${prefix}__FIT_ISOVF.nii.gz"
    touch "${prefix}__FIT_ICVF.nii.gz"
    touch "${prefix}__FIT_ECVF.nii.gz"
    touch "${prefix}__FIT_OD.nii.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: 1.6.0
    END_VERSIONS
    """
}
