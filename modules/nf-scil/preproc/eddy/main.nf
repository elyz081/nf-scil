

process PREPROC_EDDY {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_1.6.0.sif':
        'scilus/scilus:1.6.0' }"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(rev_dwi), path(rev_bval), path(rev_bvec), path(corrected_b0s), path(topup_fieldcoef), path(topup_movpart)

    output:
    tuple val(meta), path("*__dwi_corrected.nii.gz"), emit: dwi_corrected
    tuple val(meta), path("*__bval_eddy"), emit: bval_corrected
    tuple val(meta), path("*__dwi_eddy_corrected.bvec"), emit: bvec_corrected
    tuple val(meta), path("*__b0_bet_mask.nii.gz"), emit: b0_mask

    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def slice_drop_flag = task.ext.slice_drop_correction ? "--slice_drop_correction " : ""
    def bet_topup_before_eddy_f = task.ext.bet_topup_before_eddy_f ?: ""
    def prefix_topup = task.ext.prefix_topup ? task.ext.prefix_topup : ""
    def b0_thr_extract_b0 = task.ext.b0_thr_extract_b0 ? task.ext.b0_thr_extract_b0 : ""
    def encoding = task.ext.encoding ? task.ext.encoding : ""
    def readout = task.ext.readout ? task.ext.readout : ""
    def dilate_b0_mask_prelim_brain_extraction = task.ext.dilate_b0_mask_prelim_brain_extraction ? task.ext.dilate_b0_mask_prelim_brain_extraction : ""
    def eddy_cmd = task.ext.eddy_cmd ? task.ext.eddy_cmd : "eddy_cpu"
    def bet_prelim_f = task.ext.bet_prelim_f ? task.ext.bet_prelim_f : ""

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export ANTS_RANDOM_SEED=1234

    orig_bval=$bval
    # Concatenate DWIs
    number_rev_dwi=0
    if [[ -f "$rev_dwi" ]];
    then
        mrconvert $corrected_b0s b0_corrected.nii.gz -coord 3 0 -axes 0,1,2 -nthreads 1
        bet b0_corrected.nii.gz ${prefix}__b0_bet.nii.gz -m -R\
            -f $bet_topup_before_eddy_f

        scil_concatenate_dwi.py ${prefix}__concatenated_dwi.nii.gz ${prefix}__concatenated_dwi.bval ${prefix}__concatenated_dwi.bvec -f\
            --in_dwis ${dwi} ${rev_dwi} --in_bvals ${bval} ${rev_bval}\
            --in_bvecs ${bvec} ${rev_bvec}

        number_rev_dwi=\$(scil_print_header.py ${rev_dwi} --key dim | sed "s/  / /g" | sed "s/  / /g" | rev | cut -d' ' -f4-4 | rev)

        dwi=${prefix}__concatenated_dwi.nii.gz
        bval=${prefix}__concatenated_dwi.bval
        bvec=${prefix}__concatenated_dwi.bvec
    else
        dwi=${dwi}
        bval=${bval}
        bvec=${bvec}
    fi

    # If topup has been run before
    if [[ -f "$topup_fieldcoef" ]]
    then
        scil_prepare_eddy_command.py \${dwi} \${bval} \${bvec} ${prefix}__b0_bet_mask.nii.gz\
            --topup $prefix_topup --eddy_cmd $eddy_cmd\
            --b0_thr $b0_thr_extract_b0\
            --encoding_direction $encoding\
            --readout $readout --out_script --fix_seed\
            --n_reverse \${number_rev_dwi}\
            --lsr_resampling\
            $slice_drop_flag
    else
        scil_extract_b0.py \${dwi} \${bval} \${bvec} ${prefix}__b0.nii.gz --mean\
            --b0_thr $b0_thr_extract_b0 --force_b0_threshold
        bet ${prefix}__b0.nii.gz ${prefix}__b0_bet.nii.gz -m -R -f $bet_prelim_f
        scil_image_math.py convert ${prefix}__b0_bet_mask.nii.gz ${prefix}__b0_bet_mask.nii.gz --data_type uint8 -f
        maskfilter ${prefix}__b0_bet_mask.nii.gz dilate ${prefix}__b0_bet_mask_dilated.nii.gz\
            --npass $dilate_b0_mask_prelim_brain_extraction -nthreads 1
        scil_image_math.py multiplication ${prefix}__b0.nii.gz ${prefix}__b0_bet_mask_dilated.nii.gz\
            ${prefix}__b0_bet.nii.gz

        scil_prepare_eddy_command.py \${dwi} \${bval} \${bvec} ${prefix}__b0_bet_mask.nii.gz\
            --eddy_cmd $eddy_cmd --b0_thr $b0_thr_extract_b0\
            --encoding_direction $encoding\
            --readout $readout --out_script --fix_seed\
            $slice_drop_flag
    fi

    echo "--very_verbose" >> eddy.sh
    sh eddy.sh
    scil_image_math.py lower_threshold dwi_eddy_corrected.nii.gz 0 ${prefix}__dwi_corrected.nii.gz

    if [[ \$number_rev_dwi -eq 0 ]]
    then
        mv dwi_eddy_corrected.eddy_rotated_bvecs ${prefix}__dwi_eddy_corrected.bvec
        mv \${orig_bval} ${prefix}__bval_eddy
    else
        scil_validate_and_correct_eddy_gradients.py dwi_eddy_corrected.eddy_rotated_bvecs \${bval} \${number_rev_dwi} ${prefix}__dwi_eddy_corrected.bvec ${prefix}__bval_eddy
    fi


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: 1.6.0
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_image_math.py -h
    maskfilter -h
    bet -h
    scil_extract_b0.py -h
    scil_validate_and_correct_eddy_gradients.py -h
    scil_concatenate_dwi.py -h
    mrconvert -h
    scil_prepare_eddy_command.py -h
    scil_print_header.py -h

    touch ${prefix}__dwi_corrected.nii.gz
    touch ${prefix}__bval_eddy
    touch ${prefix}__dwi_eddy_corrected.bvec
    touch ${prefix}__b0_bet_mask.nii.gz


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: 1.6.0
        mrtrix: \$(dwidenoise -version 2>&1 | sed -n 's/== dwidenoise \\([0-9.]\\+\\).*/\\1/p')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')

    END_VERSIONS
    """
}
