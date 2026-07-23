# ephys nextflow pipeline
trying out the nextflow ephys pipeline: https://github.com/AllenNeuralDynamics/aind-ephys-pipeline
paper: https://www.biorxiv.org/content/10.1101/2025.11.12.687966v1.full.pdf

## Setup
The pipeline is orchestrated by the main [repo](https://github.com/AllenNeuralDynamics/aind-ephys-pipeline). Each step in the pipeline has its own repo which makes the setup a bit complicated. For example, to change something in preprocessing, I have to clone and edit the preprocessing repo. Then, I have to edit the main_multi_backend.nf to clone the correct repos during pipelines run, and capsule_versions.env to point to the correct commit hash.

So just to be aware that to make edits can involve (at least) these three steps:
- clone relevant repo and make edit
- change main_multi_backend.nf to clone correct repo
- change capsule_versions.env to point to correct hashes

## Submission on myriad
- by default the designed for slurm - myriad is SGE. made a new config file: aind-ephys-pipeline/pipeline/nextflow_sge.config
- also need new job submission script: aind-ephys-pipeline/pipeline/sge_submit.sh
- my nextflow is setup through PATH and probably bashrc - other users may need to set up

- TMP dir too small for singularity image. export tmp wd in scratch:
```
export APPTAINER_TMPDIR=$HOME/Scratch/apptainer_tmp
export SINGULARITY_TMPDIR=$HOME/Scratch/apptainer_tmp
mkdir -p $APPTAINER_TMPDIR
```

And in config:
        `cacheDir = "${System.getenv('HOME')}/Scratch/.apptainer/pull"`


need to add the below to main_multi_backend.nf in job dispatch otherwise it doesn't find input.
```
    export DATA_PATH="\${TASK_DIR}/capsule/data/ecephys_session"
    export INPUT_DATA_FOLDER="\${TASK_DIR}/capsule/data/ecephys_session"
    ./run --input ${params.input} ${job_dispatch_args}
```

### a note about arrays
for spike glx data, each session is processed separately and the script must be submitted as an array, e.g. 
`qsub -t 1-5 aind-ephys-pipeline/pipeline/sge_submit.sh SARAH_SPIKEGLX`
and the session data is pulled in the sge_submit.sh.


## Errors

### Spike Interface update
Got this error: ImportError: cannot import name 'DetectPeakLocallyExclusive' from 'spikeinterface.sortingcomponents.peak_detection'. Claude guessed it was a version mismatch.

AIND updated the pipeline in [April 2026] (https://github.com/AllenNeuralDynamics/aind-ephys-pipeline/commit/0ab5088668ec878fc4430df7a8e090a75e9815d5) which should fix the error.

So I deleted the old apptainer image and ran the pipeline again: rm /home/ucsagil/Scratch/.apptainer/pull/ghcr.io-allenneuraldynamics-aind-ephys-pipeline-base-si-0.103.2.img

### Neuropixels Record Node
There is a folder called "Record Node 101". At some point, this is used in a parameter name, which is saved relative to the data dir. So if the param name begins with data dir name, it strips it from the param and something doesn't match up.

TLDR: don't use "Record Node X" as data path

### When timestamps are not supplied
recordings without external TTL sync (like manual stimulation experiments) produce an empty timestamps.npy. In the [job-dispatch repo](https://github.com/AllenNeuralDynamics/aind-ephys-job-dispatch), there is a `run_capsule.py` script that loads data. It contains a load_sync_timestamps=True arg that causes the pipeline to derive a duration of 0 and fail if timestamps are not recorded. There is an argument --skip-timestamps-check for this exact scenario but in the original code, this arg only affects the post-read validation, not the read itself. 

So I forked the [repo](https://github.com/UCL-Biosciences/aind-ephys-job-dispatch/tree/fix/skip-sync-timestamps-openephys) and [edited the load_sync_timestamps arg](https://github.com/UCL-Biosciences/aind-ephys-job-dispatch/commit/adf8f45be66559c9d2062bc9ae9aa9bbed6f39d8). If this work, I will propose as a PR to main job-dispatch repo.

Commit hash for the update in my fork: adf8f45be66559c9d2062bc9ae9aa9bbed6f39d8

Also updated hash in capsule_versions.env and pointed main_multi_backend.nf to the forked repo: clone_repo "https://github.com/UCL-Biosciences/aind-ephys-job-dispatch.git" "${params.versions['JOB_DISPATCH']}"

#### Timestamps fix 2
Visualisations also uses timestamps. There is a setting that resets time stamps in job dispatch (that runs through pipeline json metadata). It currently checks for timestamp format. 

the case where no timestamps are supplied was not triggering that.

I didn't edit current flag as the logic is not identical. check timestamps is not the same as ignore timestamps because they don't exist.

Updating the run_capsule commit hash: b09c2df44729ab27424f5f11db90d4db69094000, then fixing typo: a1a5d4275b9edba70728a10fba2bbba7360f5a1d.
- maybe need to also say only load_sync_timestamps if NO_TIMESTAMPS is false. Changed in commit f9b5a4c4b9038ede9807b5fdac32a91f0f945353
- default debug option for when params are entered: 34ad23f3eaf7ac65280ec72c95b0156598471951
- typo for the above: 3644819ddc20018cec72beb65ae670eecd02cde3

Updated capsule_versions.env

Since no params file, added flag in the sge script: --no-timestamps. But this didn't work...

So added an awkward tmp params file to the top of the script. The problem is that this means the params file overwrites all arguments given in the nextflow command, so we also need to add input type to the params file (for open ephys).
    echo '{"job_dispatch": {"no_timestamps": true, "input": "openephys"}}' > $PARAMS_FILE

**note I reverted to aind preprocessing in commit 75d40a0c4e1d635661717c04e89d0e28e58aeca2.
Added timestamps manually so not using params file at the moment and realised the fork correcting
preprocessing is not complete**

#### timestamps fix 3 (today I choose the easy life)
Decided to try adding time data before running the pipeline. if this works, it will at least confirm that we can run open ephys data through the pipeline. Can then decide whether to pursue again the timestamp fixes.

Claude wrote some code that reconstructs missing Open Ephys timestamps from sample_numbers.npy + sampling rate. For sessions without external TTL sync, Open Ephys writes an empty (or all-zero) timestamps.npy per continuous stream. This script derives real timestamps as:
 
    timestamps = sample_numbers / sample_rate
 
using the per-stream sample_rate declared in structure.oebin, and writes them back into the stream's continuous/ folder (backing up whatever was there first).
 
Usage:
    python3 reconstruct-OpenEphys-timestamps.py.py /path/to/.../experiment1/recording1
 
    # Dry run (just report what it would do, don't write anything):
    python3 reconstruct-OpenEphys-timestamps.py.py /path/to/.../recording1 --dry-run

file is currently here: /home/ucsagil/Scratch/projects/ephys/reconstruct-OpenEphys-timestamps.py

#### preprocessing with params
*Not using this currently* see UCL-Biosciences preprocessing repo, PR1.
If you provide params via ${PARAMS_FILE:+--params_file $PARAMS_FILE}, preprocessing capsule follows some logic that breaks. I forked [preprocessing repo ](https://github.com/jdgilbert245/aind-ephys-preprocessing) (note personal not Biosciences - accident), then made the change in 6aca7fce31f45da605f3905d419371ba42827d5a. 

Updated capsule versions for this and main_multi_backend.nf

#### preprocessing min duration
For the open ephys data, we added timestamps manually. But the recording is 20 seconds, which is less than the default minimum.

I want to be able to control this from the CL so added this is an option:
1. read the flag in main_multi_backend.nf
`def min_dur_arg = params.containsKey('min_preprocessing_duration') ? "--min-duration-for-preprocessing ${params.min_preprocessing_duration}" : ""`

2. Change the line that runs preprocessing capsule
`./run ${min_dur_arg} ${motion_arg} ${preprocessing_args} ${job_args}`

3. add the flag to sge_submit: `   --min_preprocessing_duration 20 \`

This is all done on main branch of aind-ephys-pipeline.

There is an associated motion estimation step that could fail with this short recording. Added the same option to skip motion estimate:
```
def motion_arg  = params.containsKey('motion') ? "--motion ${params.motion}" : ""
`./run ${min_dur_arg} ${motion_arg} ${preprocessing_args} ${job_args}`
--motion skip # add to CL in sge_submit
```


### processing QC
Three independent bugs found in aind-ephys-processing-qc. All three patched and confirmed non-duplicated/non-overlapping in the code. Pending: full pipeline re-run to confirm behaviour end-to-end.

Multi-segment crash, event QC [UNCONFIRMED]
QC crash: "Multi-segment object. Provide 'segment_index'"
- Symptom: quality_control crashes with "Multi-segment object.
  Provide 'segment_index'" in generate_event_qc.

- Why: multi-day recordings built with si.append_recordings() end up
  as one multi-segment recording (one segment per day). QC's event
  code assumes only one segment and crashes when there's more than
  one.

- Fix: UCL-Biosciences/aind-ephys-processing-qc, branch
  fix/multi-segment-and-broken-relative-paths. Patches QC to look up
  saturation event times per-segment instead of on the whole
  recording at once.

  Multi-segment crash, drift QC [UNCONFIRMED]
- Symptom: "segment_index 1 not found in peaks data" crash in
  generate_drift_qc (specifically plot_drift_raster_map).
- Cause: a separate multi-segment bug in a different function to the
  one above — drift QC pulls peaks/peak locations and only had data
  for segment 0, then failed when asked to plot segment 1.
- Fix: patched generate_drift_qc to handle multi-segment peaks data.
  (Confirmed this is unrelated to the event QC fix - touches a
  different function, no overlap.)

QC silent failure: "Error loading preprocessed data..." + huge fake
saturation counts
[UNCONFIRMED - patched, not yet verified on a full re-run]

- Symptom: logs show "Error loading preprocessed data..." followed
  by an implausibly huge saturation event count (100M+).

- Why: the preprocessed recording remembers its data folder as a
  relative path (e.g. "../../../../data/spikeglx/concat_session").
  That path only works from the exact folder depth it was saved at -
  Nextflow tasks don't all sit at that same depth, so the path
  silently fails to resolve. QC then falls back to computing
  saturation on raw (unfiltered, unreferenced) data instead of the
  preprocessed recording, which produces nonsense event counts.

- Fix (round 1): UCL-Biosciences/aind-ephys-processing-qc, branch
  fix/multi-segment-and-broken-relative-paths. Patches QC to search
  the task's data folder for a folder/file matching the broken path's
  basename, and use that instead.

- Fix (round 2): the basename search alone risked silently
  substituting the wrong path if some other unrelated node also
  failed to resolve (e.g. a whitening matrix or motion folder).
  Refined to check each JSON node's "class" field first, confirming
  it's actually a raw recording reader (SpikeGLX/OpenEphys/
  NeuroScope/Intan) before substituting - so only the actual broken
  recording path gets fixed, and any other broken path is left alone
  with its existing warning instead of being rewritten incorrectly.
  Checked for duplicate/overlapping code after this change (grep +
  git log on the branch) - clean, single definition, built on top of
  round 1 rather than a competing copy.

- Still pending: confirm both rounds together via a full pipeline
  re-run before removing [UNCONFIRMED].


All three transferred via git format-patch / git am (not hand-edited) based on patch files generated by Claude. Verified no duplicate function definitions across the three patches via grep + git log on the branch.

Pending: confirm all three via a successful full pipeline re-run, then remove [UNCONFIRMED] tags.

## Input data
the pipeline handles:
- SpikeGLX
- Open Ephys
- NWB
- SpikeInterface
- AIND

This has ephys test data where files are not too large: https://gin.g-node.org/NeuralEnsemble/ephy_testing_data. but i think they are simulated. Trying this.

Note, I downloaded git-annex files (which I think is a link to the git location of the file) instead of the files themselves. Which looked like a "file not found" apptainer error, but was because the files were not actually the files! so to download, you need to clone the repo (https://gin.g-node.org/NeuralEnsemble/ephy_testing_data) then git annext to download the data, not just the files!

This worked for job_dispatch and pre_processing, great! But is not long enough for ful pipeline.

The pipeline also has a script for generating data which is here: /home/ucsagil/Scratch/projects/ephys/aind-ephys-pipeline/sample_dataset/nwb/sample.nwb

