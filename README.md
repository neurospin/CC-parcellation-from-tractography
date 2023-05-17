# CC-parcellation-from-tractography
Parcellation of the mid-sagittal section of the **corpus callosum** (CC) based on bilateral homotopic connectivity

This compendium of code accompanies the following publication:
Fraize, J., Convert, G., Leprince, Y., Sylvestre-Marconville, F., Kerdreux, E., Auzias, G., Lefèvre, J., Delorme, R., Elmaleh-Bergès, M., Hertz-Pannier, L., & Germanaud, D. (2023). Mapping corpus callosum surface reduction in fetal alcohol spectrum disorders with sulci and connectivity-based parcellation. *Frontiers in Neuroscience - Neurodevelopment*. DOI: [10.3389/fnins.2023.1188367](https://doi.org/10.3389/fnins.2023.1188367).

## Introduction

These are the processing scripts that implement key steps of our pipeline were to perform parcellation of the mid-sagittal section of the corpus callosum based on bilateral homotopic connectivity (article to be published).

- `SegmentationOfCorpusCallosum.py` is an addition to BrainVISA / Morphologist that generates a binary segmentation of the midsagittal section of corpus callosum.

- `segcc.sh` performs the actual segmentation of the midsagittal section of corpus callosum into seven regions, based on a whole-brain tractogram and a “lobar” cortical parcellation.


## Installation

These scripts work in a GNU/Linux environment. The external dependencies are:

- [MRtrix3](https://www.mrtrix.org/) (tested with version 3.0.3)
- [BrainVISA](https://brainvisa.info/) (tested with version 5.1.1)

Both packages must be installed and their commands must be available on the `PATH`.

Furthermore, in order to use `SegmentationOfCorpusCallosum.py`, you must first install it as a “personal” BrainVISA process:

```shell
mkdir -p ~/.brainvisa/processes
cp SegmentationOfCorpusCallosum.py ~/.brainvisa/processes/SegmentationOfCorpusCallosum.py
```

## Usage

### Generating the mid-sagittal section of corpus callosum

Once the process is installed, you can launch the `brainvisa` command and find the process in the graphical user interface, under “My processes”.

Before using this process, make sure that you have imported your data in a BrainVISA database, and run the Morphologist pipeline (see the documentation on [brainvisa.info](https://brainvisa.info/)).

After Morphologist is complete, open “Segmentation of Corpus Callosum” (found under “My processes”). Fill in the first parameter (_t1mri\_nobias_) and all remaining values should be automatically deduced. Hit _Run_, the process will run for a couple of minutes.

You should always check quality the output (_corpus\_callosum\_mask\_26c). In many cases you will need to retouch the result manually, usually to remove the fornix. For that, you can use the pencil icon next to the resulting file, and edit the region of interest in Anatomist. Close the window when you are done editing, you will then be prompted to save the edited ROI.


### Performing connectivity-based parcellation of corpus callosum

The [segcc.sh](./segcc.sh) script is the entry point to perform connectivity-based parcellation of corpus callosum. It expects a specific organization of the input data, see the comments [in the script itself](./segcc.sh) for details. You can run this script from the command-line:

```shell
./segcc.sh /path/to/data subjectName
```

This script needs the following inputs from the anatomical pipeline (BrainVISA/Morphologist):

- mask of the corpus callosum (see above)
- cortical parcellation of the left hemisphere
- cortical parcellation of the right hemisphere

It also needs these inputs from the diffusion pipeline (FSL / MRtrix):

- DWI-to-T1 transformation estimated with FSL FLIRT
- DWI image used as FLIRT "-in"
- T1 image used as FLIRT "-ref"
- whole-brain tractogram
- SIFT2 weights of the tractogram

Based on this input data, it will perform these processing steps:
1. Transform the cortical parcellation into DWI space
2. Select tracks going through the corpus callosum
3. Label and separate CC tracks according to their cortical endpoint
4. Create Track Density Images for each sub-track
5. Average left and right track density maps
6. Vote

Final outputs of this script are:

- Result of the vote on the midsagittal section of CC, in anatomical (T1) space:
  `${subjectName}_segmented_cc_2T1_mean.nii.gz`
- Result of the vote on the midsagittal section of CC, in diffusion (dwi) space:
  `${subjectName}_segmented_cc_2dwi_mean.nii.gz`
- Result of the vote extended over a few parasagittal slices (for visualization),
  in anatomical (T1) space:
  `${subjectName}_segmented_cc_2T1_mean.nii.gz`
- Result of the vote extended over a few parasagittal slices (for visualization),
  in diffusion (dwi) space:
  `${subjectName}_segmented_cc_2dwi_mean.nii.gz`

Each “lobe” is assigned a given label in the input cortical segmentation, and referred to by a given label in the output parcellation, according to the following table:

|     “lobe”       | left label  | right label | final label |
| -----------------| ----------- | ----------- | ----------- |
| occipitotemporal | 210         | 200         | 20          |
| parietal         | 310         | 300         | 30          |
| postcentral      | 410         | 400         | 40          |
| precentral       | 510         | 500         | 50          |
| frontal          | 610         | 600         | 60          |
| prefrontal       | 710         | 700         | 70          |
| orbitofrontal    | 810         | 800         | 80          |


## Licence

[CC-parcellation-from-tractography](https://github.com/neurospin/CC-parcellation-from-tractography) © 2023 by Gabrielle Convert, Clara Fischer, Justine Fraize, Yann Leprince, David Germanaud (INSERM, CEA) is licensed under [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/?ref=chooser-v1)
