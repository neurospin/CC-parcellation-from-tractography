# This is a BrainVISA process, to use it you have to install it as a “personal”
# BrainVISA process:
#
#     mkdir -p ~/.brainvisa/processes
#     cp SegmentationOfCorpusCallosum.py ~/.brainvisa/processes/SegmentationOfCorpusCallosum.py
#
# After this is done, it will become available in the brainvisa user interface
# under “My processes”.
#
# Initial author: Clara FISCHER (2021)
# Contributor: Gabrielle CONVERT (2021, 2022)
# Contributor: Yann LEPRINCE (2022, 2023)
#
# CC-parcellation-from-tractography © 2023 by Gabrielle Convert, Clara Fischer,
# Justine Fraize, Yann Leprince, David Germanaud (INSERM, CEA), licensed under
# CC BY 4.0.


from brainvisa.processes import *
from brainvisa import registration

import numpy
from soma import aims


name = 'Segmentation of Corpus Callosum'
userLevel = 0

# Argument declaration
signature = Signature(
    't1mri_nobias', ReadDiskItem(
        'T1 MRI Bias Corrected',
        'Aims readable volume formats'),
    'histo_analysis', ReadDiskItem(
        'Histo Analysis',
        'Histo Analysis'),
    'brain_mask', ReadDiskItem(
        'T1 Brain Mask',
        'Aims readable volume formats'),
    'edges', ReadDiskItem(
        'T1 MRI Edges',
        'Aims readable volume formats'),
    'commissure_coordinates', ReadDiskItem(
        'Commissure coordinates',
        'Commissure coordinates'),
    'left_grey_white', ReadDiskItem(
        'Morphologist Grey White Mask',
        'Aims readable volume formats',
        requiredAttributes={'side': 'left'}),
    'right_grey_white', ReadDiskItem(
        'Morphologist Grey White Mask',
        'Aims readable volume formats',
        requiredAttributes={'side': 'right'}),
    'talairach_transformation', ReadDiskItem(
        'Transform Raw T1 MRI to Talairach-AC/PC-Anatomist',
        'Transformation matrix'),
    'do_greywhite_before_cc_mask', Boolean(),
    'grey_white', WriteDiskItem(
        'Morphologist Grey White Mask',
        'Aims writable volume formats',
        requiredAttributes={'side': 'both'}),
    'interhemispheric_plane', WriteDiskItem(
        'Label Volume',
        'Aims writable volume formats'),
    'corpus_callosum_mask_6c', WriteDiskItem(
        'Corpus Callosum mask',
        'Aims writable volume formats'),
    'corpus_callosum_mask_26c', WriteDiskItem(
        'Corpus Callosum mask',
        'Aims writable volume formats'),
)

# Default values
def initialization(self):
    def linkCC1(mask):
        if self.left_grey_white is not None:
            return self.left_grey_white.fullPath().replace('Lgrey_white',
                                                           'corpus_callosum_mask_6c')

    def linkCC2(mask):
        if self.left_grey_white is not None:
            return self.left_grey_white.fullPath().replace('Lgrey_white',
                                                           'corpus_callosum_mask_26c')

    def linkGreyWhite(mask):
        if self.left_grey_white is not None:
            return self.left_grey_white.fullPath().replace('Lgrey', 'grey')

    def linkIHP(mask):
        if self.left_grey_white is not None:
            return self.left_grey_white.fullPath().replace('Lgrey_white',
                                                           'interhemispheric_plane')

    self.linkParameters('histo_analysis', 't1mri_nobias')
    self.linkParameters('left_grey_white', 't1mri_nobias')
    self.linkParameters('right_grey_white', 't1mri_nobias')
    self.linkParameters('brain_mask', 't1mri_nobias')
    self.linkParameters('edges', 't1mri_nobias')
    self.linkParameters('commissure_coordinates', 't1mri_nobias')
    self.linkParameters('talairach_transformation', 't1mri_nobias')

    self.addLink('grey_white', 'left_grey_white', linkGreyWhite)
    self.addLink('interhemispheric_plane', 'left_grey_white', linkIHP)
    self.addLink('corpus_callosum_mask_6c', 'left_grey_white', linkCC1)
    self.addLink('corpus_callosum_mask_26c', 'left_grey_white', linkCC2)

    self.do_greywhite_before_cc_mask = True


def execution( self, context ):

    if self.do_greywhite_before_cc_mask:
        context.write('Computing grey-white classification on the whole brain...')
        command = ['VipGreyWhiteClassif',
                   '-i', self.t1mri_nobias,
                   '-h', self.histo_analysis,
                   '-m', self.brain_mask,
                   '-edges', self.edges,
                   '-P', self.commissure_coordinates,
                   '-o', self.grey_white,
                   '-l', 255, '-w', 't', '-a', 'R' ]
        context.system(*command)

    # create inter hemispheric plane
    ihp = context.temporary('NIFTI-1 image')
    context.system('AimsThreshold', '-i', self.grey_white, '-o', ihp,
                   '-t', 0, '-m', 'di', '-b')
    context.system('AimsMorphoMath', '-i', ihp, '-o', ihp,
                   '-m', 'clo', '-r', 5)
    ihp_aims = aims.read(ihp.fullPath())
    tal = aims.read(self.talairach_transformation.fullPath())
    ar = numpy.asarray(ihp_aims)
    #dihp = aims.AimsData(ihp_aims)
    roiit = aims.getRoiIterator(ihp_aims)

    todel = []
    while roiit.isValid():
        mit = roiit.maskIterator()
        while mit.isValid():
            q = tal.transform(mit.valueMillimeters())
            if q[0] < -1.1 or q[0] > 1.1:
                todel.append(mit.value())
            mit.next()
        roiit.next()
    for v in todel:
        ar[v[0], v[1], v[2]] = 0

    ihp_6c = context.temporary('NIFTI-1 image')
    aims.write(ihp_aims, ihp.fullPath())

    # make the ih plane one voxel large / 26 neighbourhood
    context.system('VipSkeleton', '-i', ihp, '-so', ihp,
                   '-sk', 's', '-im', 'a', '-fv', 'n', '-p', 0)
    context.system('AimsThreshold', '-i', ihp, '-o', self.interhemispheric_plane,
                   '-t', 0, '-m', 'di', '-b')

    # make the ih plane one voxel large / 6 neighbourhood
    ihp_aims = aims.read(ihp.fullPath())
    ihp_arr = numpy.asarray(ihp_aims)
    for x in range(int(ihp_aims.getSizeX())):
        for y in range(int(ihp_aims.getSizeY())):
            for z in range(int(ihp_aims.getSizeZ())):
                if ihp_arr[x, y, z, 0] == 60:
                    nv = 0
                    if ihp_arr[x-1, y, z] != 0:
                        nv += 1
                    if ihp_arr[x+1, y, z] != 0:
                        nv += 1
                    if ihp_arr[x, y-1, z] != 0:
                        nv += 1
                    if ihp_arr[x, y+1, z] != 0:
                        nv += 1
                    if ihp_arr[x, y, z-1] != 0:
                        nv += 1
                    if ihp_arr[x, y, z+1] != 0:
                        nv += 1
                    if nv == 2 or nv == 3:
                        ihp_arr[x, y+1, z] = 120
    aims.write(ihp_aims, ihp.fullPath())
    context.system('AimsThreshold', '-i', ihp, '-o', ihp,
                   '-t', 0, '-m', 'di', '-b')

    # compute white mask
    white = context.temporary('NIFTI-1 image')
    context.system('AimsThreshold', '-i', self.grey_white, '-o', white,
                   '-t', 200, '-m', 'ge')
    # close white mask
    context.system('AimsMorphoMath', '-i', white, '-o', white,
                   '-m', 'ero',  '-r', 1.1)
    #context.system('AimsMorphoMath', '-i', white, '-o', white,
                   #'-m', 'clo',  '-r', 2)

    # keep all connected components, then filter them out
    cc = context.temporary('NIFTI-1 image')
    context.system('AimsMask', '-i', white, '-m', ihp, '-o', cc)
    context.system('AimsConnectComp', '-i', cc, '-o', cc,
                   '-c', 26, '-s', 0)

    minradius = 15
    maxradius = 50
    minradius *= minradius  # square
    maxradius *= maxradius

    vol = aims.read(cc.fullPath())
    arr = numpy.asarray(vol)
    roiit = aims.getRoiIterator(vol)
    todel = []
    cent = aims.Point3df(0, 10, 0)
    while roiit.isValid():
        mit = roiit.maskIterator()
        p = aims.Point3df(0, 0, 0)
        n = 0
        out = 0
        comp = int(roiit.regionName())
        while mit.isValid():
            q = tal.transform(mit.valueMillimeters())
            p += q
            r = (q - cent).norm2()
            if r < minradius or r > maxradius:
                out += 1
            n += 1
            mit.next()
        p /= n
        if (p[2] >= -5 or p[2] <= -40 or p[1] <= -40 or p[1] >= 55
                or out > 0.15 * n):
            todel.append(comp)
        roiit.next()
    for v in todel:
        arr[arr == v] = 0

    aims.write(vol, cc.fullPath())

    # merge if several components
    context.system('AimsThreshold', '-i', cc,
                   '-o', self.corpus_callosum_mask_6c,
                   '-t', 0, '-m', 'di', '-b')
    context.system('AimsMorphoMath', '-i', self.corpus_callosum_mask_6c,
                   '-o', self.corpus_callosum_mask_6c,
                   '-m', 'dil',  '-r', 1.1)
    context.system('AimsMorphoMath', '-i', self.corpus_callosum_mask_6c,
                   '-o', self.corpus_callosum_mask_6c,
                   '-m', 'clo',  '-r', 2.1)
    # mask by ihp in 26 connexity
    context.system('AimsMask', '-i', self.corpus_callosum_mask_6c,
                   '-o', self.corpus_callosum_mask_26c,
                   '-m', self.interhemispheric_plane)

    tm = registration.getTransformationManager()
    tm.copyReferential(self.t1mri_nobias, self.grey_white)
    tm.copyReferential(self.t1mri_nobias, self.interhemispheric_plane)
    tm.copyReferential(self.t1mri_nobias, self.corpus_callosum_mask_6c)
    tm.copyReferential(self.t1mri_nobias, self.corpus_callosum_mask_26c)
