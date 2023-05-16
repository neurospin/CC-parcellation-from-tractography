#!/bin/bash
#
# Parcellation of the corpus callosum :
# - Upsampled corpus callosum midsagittal section
# - Average unilateral connectivity
#
#
# Initial author: Gabrielle CONVERT (2021, 2022)
# Contributor: Yann LEPRINCE (2022, 2023)
#
# CC-parcellation-from-tractography © 2023 by Gabrielle Convert, Clara Fischer,
# Justine Fraize, Yann Leprince, David Germanaud (INSERM, CEA), licensed under
# CC BY 4.0.

set -e  # exit upon errors

display_usage() {
    echo "$(basename "$0") subjectBase subjectList"

    echo "\
This script obtains TDI maps (track density images) from the
whole-brain tractogram and a lobar cortical parcellation,
and performs the majority vote on the mid-sagittal section
of the corpus callosum.

It takes the following arguments:
    1) The full path to the folder containing the subjects' data
    2) subjectList (whitespace-separated list of subject identifiers)
"
}


if [ $# -ne 2 ]
then
    display_usage
    exit 2
fi

self_dir=$(dirname -- "$0")

#Assigning the user input to argument
subjectBase=$1
subjectList=$2

#####################
# Global parameters #
#####################
#
# process1, process, mars_atlas_folder, and method are used as filename
# components and directory names, they can be used to separate the processed
# data according to the methods and parameters used, if you want to compare
# variants of the processing.
process1=dynamic_10Mio
process=${process1}
mars_atlas_folder=mars_atlas_aprcs
method=PROB_epireg
# For the selection of tracks that cross the midsagittal section of CC, tracks
# need to be upsampled to a step size that is smaller than the voxel size. For
# instance, in the original study we have used a voxel spacing of 0.5 mm, so a
# track step size of 0.4 mm is appropriate.
tckupsample_step_size=0.4


for subjectName in $subjectList
do
    resultDirectory=$subjectBase/$subjectName/segmentation_cc/$mars_atlas_folder
    maskCC=$resultDirectory/$process/${subjectName}_maskCC_registered2dwi.nii.gz

    mkdir -p "$resultDirectory/$process"

    # Inputs:
    # =======
    # From the diffusion pipeline (FSL preprocessing, MRtrix tractography):
    # - DWI-to-T1 transformation estimated with FSL FLIRT:
    #   $subjectBase/$subjectDirectory/$subjectName/dwi/preproc/out/unwarp_dwi2t1.mat
    # - DWI image used as FLIRT "-in":
    #   $subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_b0_denoised.nii.gz
    # - T1 image used as FLIRT "-ref":
    #   $subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_5tt_unregistered.nii.gz
    # - whole-brain tractogram:
    #   $subjectBase/$subjectName/dwi/MRTrix/PROB_epireg/${subjectName}_tcks_$process1.tck
    # - SIFT2 weights of the tractogram:
    #   $subjectBase/$subjectName/dwi/MRTrix/PROB_epireg/${subjectName}_weights_$process1.txt
    #
    # From the anatomical pipeline (BrainVISA/Morphologist):
    # - mask of the corpus callosum:
    #   $subjectBase/$subjectName/t1mri/default_acquisition/upsampled_analysis/segmentation/corpus_callosum_mask_26c_${subjectName}.nii.gz
    # - cortical parcellation of the left hemisphere:
    #   $subjectBase/$subjectName/segmentation_cc/$mars_atlas_folder/${subjectName}_Lparcellation.nii.gz
    # - cortical parcellation of the right hemisphere:
    #   $subjectBase/$subjectName/segmentation_cc/$mars_atlas_folder/${subjectName}_Rparcellation.nii.gz
    #
    # Outputs:
    # ========
    # All final outputs are written in $resultDirectory
    # - Result of the vote on the midsagittal section of CC, in anatomical (T1) space:
    #   $resultDirectory/$process/${subjectName}_segmented_cc_2T1_mean.nii.gz
    # - Result of the vote on the midsagittal section of CC, in diffusion (dwi) space:
    #   $resultDirectory/$process/${subjectName}_segmented_cc_2dwi_mean.nii.gz
    # - Result of the vote extended over a few parasagittal slices for visualization,
    #   in anatomical (T1) space:
    #   $resultDirectory/$process/${subjectName}_segmented_cc_2T1_mean.nii.gz
    # - Result of the vote extended over a few parasagittal slices for visualization,
    #   in diffusion (dwi) space:
    #   $resultDirectory/$process/${subjectName}_segmented_cc_2dwi_mean.nii.gz
    #
    # Each "lobe" is assigned a given label in the input cortical
    # segmentation, and referred to by a given label in the output
    # parcellation, according to the following table:
    #
    # +------------------+-------------+-------------+-------------+
    # |     "lobe"       | left label  | right label | final label |
    # +------------------+-------------+-------------+-------------+
    # | occipitotemporal | 210         | 200         | 20          |
    # +------------------+-------------+-------------+-------------+
    # | parietal         | 310         | 300         | 30          |
    # +------------------+-------------+-------------+-------------+
    # | postcentral      | 410         | 400         | 40          |
    # +------------------+-------------+-------------+-------------+
    # | precentral       | 510         | 500         | 50          |
    # +------------------+-------------+-------------+-------------+
    # | frontal          | 610         | 600         | 60          |
    # +------------------+-------------+-------------+-------------+
    # | prefrontal       | 710         | 700         | 70          |
    # +------------------+-------------+-------------+-------------+
    # | orbitofrontal    | 810         | 800         | 80          |
    # +------------------+-------------+-------------+-------------+

    ########################### STEP 1 #############################
    #      Transform the cortical parcellation into DWI space      #
    ################################################################
    transformconvert -force \
                     "$subjectBase/$subjectDirectory/$subjectName/dwi/preproc/out/unwarp_dwi2t1.mat" \
                     "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_b0_denoised.nii.gz" \
                     "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_5tt_unregistered.nii.gz" \
                     flirt_import \
                     "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt"
    mrtransform -force \
                "$subjectBase/$subjectName/t1mri/default_acquisition/upsampled_analysis/segmentation/corpus_callosum_mask_26c_$subjectName.nii.gz" \
                -linear "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt" \
                -inverse \
                "$maskCC"
    mrtransform -force\
                "$resultDirectory/${subjectName}_Lparcellation.nii.gz" \
                -linear "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt" \
                -inverse \
                "$resultDirectory/${subjectName}_Lparcellation_registered2dwi.nii.gz"
    mrtransform -force \
                "$resultDirectory/${subjectName}_Rparcellation.nii.gz" \
                -linear "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt" \
                -inverse \
                "$resultDirectory/${subjectName}_Rparcellation_registered2dwi.nii.gz"

    ########################### STEP 2 #############################
    #       Select tracks going through the corpus callosum        #
    ################################################################
    #
    # Upsample tracks so that they are sampled at a smaller step than the voxel
    # size, and select tracks that intersect the mid-sagittal section of corpus
    # callosum.
    upsampled_tracks=$(mktemp --suffix=.tck)
    tckresample -force \
                "$subjectBase/$subjectName/dwi/MRTrix/PROB_epireg/${subjectName}_tcks_$process1.tck" \
                "$upsampled_tracks" \
                -step_size "$tckupsample_step_size"
    tckedit -force\
            -include "$maskCC" \
            -tck_weights_in "$subjectBase/$subjectName/dwi/MRTrix/PROB_epireg/${subjectName}_weights_$process1.txt" \
            -tck_weights_out "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
            "$upsampled_tracks" \
            "$resultDirectory/$process/${subjectName}_cc_tracks.tck"
    rm -f "$upsampled_tracks"
    unset upsampled_tracks

    ########################### STEP 3 #############################
    #    Separate CC tracks according to their cortical endpoint   #
    ################################################################
    #
    # Label CC tracks according to their cortical endpoint
    tck2connectome -force \
                   -symmetric \
                   -zero_diagonal \
                   -scale_invnodevol \
                   -assignment_forward_search 8 \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/${subjectName}_Lparcellation_registered2dwi.nii.gz" \
                   "$resultDirectory/$process/${subjectName}_lobes_cc.csv" \
                   -out_assignment "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv"
    tck2connectome -force \
                   -symmetric \
                   -zero_diagonal \
                   -scale_invnodevol \
                   -assignment_forward_search 8 \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/${subjectName}_Rparcellation_registered2dwi.nii.gz" \
                   "$resultDirectory/$process/${subjectName}_Rspanol_cc.csv" \
                   -out_assignment "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv"

    # Apply connectome2tck to all nodes with -exclusive option to specify
    # that we only want to select tracks between the two regions
    connectome2tck -force \
                   -nodes 0,210 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,310 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,410 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,510 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,610 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,710 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,810 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Lassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,200 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,300 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,400 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,500 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,600 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,700 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"
    connectome2tck -force \
                   -nodes 0,800 -exclusive \
                   -tck_weights_in "$resultDirectory/$process/${subjectName}_weights_$process1.txt" \
                   -prefix_tck_weights_out "$resultDirectory/$process/${subjectName}_weight_" \
                   "$resultDirectory/$process/${subjectName}_cc_tracks.tck" \
                   "$resultDirectory/$process/${subjectName}_Rassignments_lobes_cc.csv" \
                   "$resultDirectory/$process/${subjectName}_cc_"

    ########################### STEP 4 #############################
    #   Create Track Density Images (tdiMaps) for each sub-track   #
    ################################################################
    #
    # Create density maps of streamlines connecting each lobe to the
    # contralateral hemisphere
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-210.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-210.tck" \
           "$resultDirectory/$process/${subjectName}_Locc_temp_20_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-310.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-310.tck" \
           "$resultDirectory/$process/${subjectName}_Lparietal_30_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-410.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-410.tck" \
           "$resultDirectory/$process/${subjectName}_Lpostcentral_40_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-510.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-510.tck" \
           "$resultDirectory/$process/${subjectName}_Lprecentral_50_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-610.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-610.tck" \
           "$resultDirectory/$process/${subjectName}_Lfrontal1_60_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-710.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-710.tck" \
           "$resultDirectory/$process/${subjectName}_Lfrontal2_70_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-810.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-810.tck" \
           "$resultDirectory/$process/${subjectName}_Lorbitofrontal_80_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-200.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-200.tck" \
           "$resultDirectory/$process/${subjectName}_Rocc_temp_20_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-300.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-300.tck" \
           "$resultDirectory/$process/${subjectName}_Rparietal_30_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-400.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-400.tck" \
           "$resultDirectory/$process/${subjectName}_Rpostcentral_40_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-500.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-500.tck" \
           "$resultDirectory/$process/${subjectName}_Rprecentral_50_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-600.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-600.tck" \
           "$resultDirectory/$process/${subjectName}_Rfrontal1_60_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-700.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-700.tck" \
           "$resultDirectory/$process/${subjectName}_Rfrontal2_70_tdiMap.nii.gz"
    tckmap -force \
           -tck_weights_in "$resultDirectory/$process/${subjectName}_weight_0-800.csv" \
           -template "$maskCC" \
           "$resultDirectory/$process/${subjectName}_cc_0-800.tck" \
           "$resultDirectory/$process/${subjectName}_Rorbitofrontal_80_tdiMap.nii.gz"

    ########################### STEP 5 #############################
    #             Average left and right density maps              #
    ################################################################
    #
    # Calculate average left-right connectivity of each lobe
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Locc_temp_20_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rocc_temp_20_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanocc_temp_20_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lparietal_30_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rparietal_30_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanparietal_30_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lpostcentral_40_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rpostcentral_40_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanpostcentral_40_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lprecentral_50_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rprecentral_50_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanprecentral_50_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lfrontal1_60_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rfrontal1_60_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanfrontal1_60_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lfrontal2_70_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rfrontal2_70_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanfrontal2_70_tdiMap.nii.gz"
    mrcalc -force \
           "$resultDirectory/$process/${subjectName}_Lorbitofrontal_80_tdiMap.nii.gz" \
           "$resultDirectory/$process/${subjectName}_Rorbitofrontal_80_tdiMap.nii.gz" \
           -add 2 -divide \
           "$resultDirectory/$process/${subjectName}_meanorbitofrontal_80_tdiMap.nii.gz"

    ########################### STEP 6 #############################
    #                            Vote                              #
    ################################################################
    #
    # Perform regularized majority vote on the average left-right connectivity
    bv python "$self_dir/regularized_vote.py" \
       --output-labels 80 70 60 50 40 30 20 \
       --no-vote-label 2 \
       "$resultDirectory/$process" \
       "$subjectName" \
       "$resultDirectory/$process/${subjectName}_meanorbitofrontal_80_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanfrontal2_70_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanfrontal1_60_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanprecentral_50_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanpostcentral_40_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanparietal_30_tdiMap.nii.gz" \
       "$resultDirectory/$process/${subjectName}_meanocc_temp_20_tdiMap.nii.gz"

    # Transform the results back into anatomical space (space of the T1-weighted
    # image)
    mrtransform -force \
                "$resultDirectory/$process/${subjectName}_segmented_cc_2dwi_mean.nii.gz" \
                -linear "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt" \
                "$resultDirectory/$process/${subjectName}_segmented_cc_2T1_mean.nii.gz"
    mrtransform -force \
                "$resultDirectory/$process/${subjectName}_segmented_cc_bis_2dwi_mean.nii.gz" \
                -linear "$subjectBase/$subjectName/dwi/MRTrix/$method/${subjectName}_dwi2T1.txt" \
                "$resultDirectory/$process/${subjectName}_segmented_cc_bis_2T1_mean.nii.gz"
done
