#!/usr/bin/env python3
#
# Perform regularized majority voting on the mid-sagittal section of the corpus
# callosum. This script is called from segcc.sh.
#
# Initial author: Gabrielle CONVERT (2022)
# Contributor: Yann LEPRINCE (2022, 2023)
#
# CC-parcellation-from-tractography © 2023 by Gabrielle Convert, Clara Fischer,
# Justine Fraize, Yann Leprince, David Germanaud (INSERM, CEA), licensed under
# CC BY 4.0.

import os
import subprocess
import sys

import numpy
from soma import aims


CONTRIB_CENTRAL_VOXEL = 0.5
CONTRIB_NEIGHBOURS = 0.5

NO_VOTE = 2
OUTPUT_LABELS = [80, 70, 60, 50, 40, 30, 20]

EXTENSION = 3


def regularize_tdis_at(tdi_array, x, y, z):
    neighbour_count = 0
    neighbour_contrib = numpy.zeros((tdi_array.shape[3],),
                                    dtype=tdi_array.dtype)
    # On parcourt tous les voisins
    for i in range(max(x-1, 0), min(x+2, tdi_array.shape[0]+1)):
        for j in range(max(y-1, 0), min(y+2, tdi_array.shape[0]+1)):
            for k in range(max(z-1, 0), min(z+2, tdi_array.shape[0]+1)):
                if tdi_array[i, j, k].max() != 0:  # if there is a vote
                    if (i, j, k) != (x ,y, z):
                        neighbour_contrib += tdi_array[i, j, k]
                        neighbour_count += 1
    if neighbour_count != 0:
        return (tdi_array[x, y, z] * CONTRIB_CENTRAL_VOXEL
                + neighbour_contrib * (CONTRIB_NEIGHBOURS / neighbour_count))
    else:
        return tdi_array[x, y, z]


def regularized_vote(result_dir, subject, tdi_filenames, output_labels):
    # Read the corpus callosum mask, to perform the vote only within the mask
    mask_cc = aims.read(os.path.join(result_dir, subject + '_maskCC_registered2dwi.nii.gz'))
    arr_cc = numpy.asarray(mask_cc)[:, :, :, 0]
    # Read track density images and stack them in a 4D NumPy array
    tdi_volumes = [aims.read(tdi_filename) for tdi_filename in tdi_filenames]
    tdi_array = numpy.concatenate([tdi_vol.np for tdi_vol in tdi_volumes],
                                  axis=3)
    tdi_array[arr_cc == 0] = 0

    # Obtain indices of all voxels within the mask
    tab_x, tab_y, tab_z = arr_cc.nonzero()

    # Find the smallest type that can contain all labels
    dtype = numpy.uint8
    for label in [0, NO_VOTE] + output_labels:
        dtype = numpy.promote_types(dtype, numpy.min_scalar_type(label))

    result = numpy.zeros_like(arr_cc, dtype=dtype)
    # TODO: choice of datatype based on actual values
    # Loop on voxels in the mask
    for x, y, z in zip(tab_x, tab_y, tab_z):
        regularized_tdis_xyz = regularize_tdis_at(tdi_array, x, y, z)
        winner_index = numpy.argmax(regularized_tdis_xyz)
        if regularized_tdis_xyz[winner_index] == 0:
            result[x, y, z] = NO_VOTE
        else:
            result[x, y, z] = output_labels[winner_index]

    result_volume = aims.Volume(result)
    result_volume.copyHeaderFrom(mask_cc.header())
    aims.write(result_volume,
               os.path.join(result_dir,
                            subject + '_segmented_cc_2dwi_mean.nii.gz'))

    # To ease visualization, extend the labels 3 slices around the central
    # slice of the midsagittal section of CC.
    extended_result = result.copy()
    central_x = int(numpy.median(tab_x))
    extended_result[central_x-EXTENSION:central_x+EXTENSION+1, tab_y, tab_z] = (
        result[tab_x, tab_y, tab_z]
    )
    extended_result_volume = aims.Volume(extended_result)
    extended_result_volume.copyHeaderFrom(result_volume.header())
    aims.write(extended_result_volume,
               os.path.join(result_dir,
                            subject + '_segmented_cc_bis_2dwi_mean.nii.gz'))


def parse_command_line(argv=sys.argv):
    """Parse the script's command line."""
    import argparse
    parser = argparse.ArgumentParser(description="""\
Perform regularized vote between the track density images for different tracks
""")
    parser.add_argument('result_dir')
    parser.add_argument('subject', help='subject identifier')
    parser.add_argument('tdi', nargs='*', help='track density images')
    parser.add_argument('--output-labels', type=int, nargs='*',
                        help='label to be assigned to output voxels for each '
                        'input track density image (default: 1, 2, 3,...)')
    parser.add_argument('--no-vote-label', type=int, default=2,
                        help='value assigned to voxels without a vote')
    args = parser.parse_args(argv[1:])
    if len(args.tdi) < 2:
        parser.error('at least two track density images must be provided')
    if args.output_labels is None:
        args.output_labels = list(range(1, len(args.tdi) + 1))
    elif len(args.output_labels) != len(args.tdi):
        parser.error('there ')
    return args


def main(argv=sys.argv):
    """The script's entry point."""
    args = parse_command_line(argv)
    return regularized_vote(args.result_dir, args.subject, args.tdi,
                            args.output_labels) or 0


if __name__ == '__main__':
    sys.exit(main())
