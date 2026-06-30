# !/bin/bash
#$ -S /bin/bash
#$ -l mem=4G # 4
#$ -l h_rt=24:00:00 # 24
#$ -cwd
#$ -j y
#$ -m be # email to be notified when the job begins and ends
#$ -N "nextflow_aind_submit"

USE_DATA=$1 # supplied with command line flag.
# can be NWB_SYNTHETIC, SHORT_SPIKEGLX, SARAH_SPIKEGLX, SARAH_SPIKEGLX_CONCAT, OPEN_EPHYS
# e.g. qsub aind-ephys-pipeline/pipeline/sge_submit.sh OPEN_EPHYS

### a note about arrays
# for spike glx data, each session is processed separately and the script must be submitted as an array, e.g.
# qsub -t 1-5 aind-ephys-pipeline/pipeline/sge_submit.sh SARAH_SPIKEGLX
# and the session data is pulled in the script below.

PARAMS_FILE=""  # default: no params file

if [ "$USE_DATA" == "NWB_SYNTHETIC" ]; then
    DATA_PATH="/home/ucsagil/Scratch/projects/ephys/aind-ephys-pipeline/sample_dataset/nwb"
    RESULTS_PATH="/home/ucsagil/Scratch/projects/ephys/results/test_run/nwb_synthetic"
    INPUT_TYPE=nwb
elif [ "$USE_DATA" == "SHORT_SPIKEGLX" ]; then
    DATA_PATH="/home/ucsagil/Scratch/projects/ephys/data/ephy_testing_data/spikeglx/multi_trigger_multi_gate/SpikeGLX/5-19-2022-CI1/5-19-2022-CI1_g0"
    RESULTS_PATH="/home/ucsagil/Scratch/projects/ephys/results/test_run/short_spikeglx"
    INPUT_TYPE=spikeglx
elif [ "$USE_DATA" == "OPEN_EPHYS" ]; then
    DATA_PATH="/myriadfs/home/ucsagil/Scratch/projects/ephys/data/Neuropixels/09241_brush_10x_2_2025-05-19_12-40-45"
    RESULTS_PATH="/myriadfs/home/ucsagil/Scratch/projects/ephys/results/test_run/Laura_neuropixels_ephys"
    INPUT_TYPE=openephys
    # create a temporary params file for this run - only this use needs no_timestamps
    PARAMS_FILE=$(mktemp /tmp/ephys_params_XXXX.json)
    echo '{"job_dispatch": {"no_timestamps": true, "input": "openephys"}, "preprocessing": {"min_preprocessing_duration": 20}}' > $PARAMS_FILE
elif [ "$USE_DATA" == "SARAH_SPIKEGLX" ]; then
    SESSIONS=$(ls /home/ucsagil/Scratch/projects/ephys/data/spikeglx)
    SESSION=$(echo $SESSIONS | cut -f $SGE_TASK_ID -d ' ')
    DATA_PATH="/home/ucsagil/Scratch/projects/ephys/data/spikeglx/$SESSION"
    RESULTS_PATH="/myriadfs/home/ucsagil/Scratch/projects/ephys/results/sarah_spikeglx/$SESSION"
    INPUT_TYPE=spikeglx
elif [ "$USE_DATA" == "SARAH_SPIKEGLX_CONCAT" ]; then
    DATA_PATH="/home/ucsagil/Scratch/projects/ephys/data/spikeglx/concat_session"
    RESULTS_PATH="/myriadfs/home/ucsagil/Scratch/projects/ephys/results/sarah_spikeglx_concat/"
    INPUT_TYPE=spikeinterface
    PARAMS_FILE=$(mktemp /tmp/ephys_params_XXXX.json)
    echo '{"job_dispatch": {"input": "spikeinterface", "spikeinterface_info": {"reader_type": "spikeinterface"}}}' > $PARAMS_FILE
else
    echo "Unknown data type: $USE_DATA"
    exit 1
fi

qalter $JOB_ID -N "nextflow_aind_${INPUT_TYPE}"

# Now redirect log with variable available
# (note the first part checks if the script is running interactively, and only redirects if it's not. Otherwise interactive session get stuck)
[[ $- != *i* ]] && exec &>> /home/ucsagil/Scratch/projects/ephys/logs/nextflow_aind_ephys_${JOB_ID}_${TASK_ID:-$INPUT_TYPE}.log

mkdir -p $RESULTS_PATH

PIPELINE_PATH="/home/ucsagil/Scratch/projects/ephys/aind-ephys-pipeline"
WORKDIR="/home/ucsagil/Scratch/projects/ephys/workdir"

export APPTAINER_TMPDIR=$HOME/Scratch/apptainer_tmp
export SINGULARITY_TMPDIR=$HOME/Scratch/apptainer_tmp
mkdir -p $APPTAINER_TMPDIR

# check if nextflow_sge_custom.config exists
if [ -f "$PIPELINE_PATH/pipeline/nextflow_sge_custom.config" ]; then
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_sge_custom.config"
else
    CONFIG_FILE="$PIPELINE_PATH/pipeline/nextflow_sge.config"
fi

echo "Using config file: $CONFIG_FILE"
echo "DATA_PATH is: [$DATA_PATH]"

# nextflow run nf-core/testpipeline -profile test,ucl_myriad \
# --outdir /myriadfs/home/ucsagil/Scratch/projects/ephys/test

# timestamps look broken in the dataset we're using for testing, so we need to disable the load_sync_timestamps option in the config file. This is a temporary workaround until we can fix the timestamps in the dataset or add as a proper parameter
# sed -i 's/"load_sync_timestamps": true/"load_sync_timestamps": false/' /home/ucsagil/Scratch/projects/ephys/workdir/71/cc7420f519347e8f779cf5349b2321/capsule/results/job_0.json

### HAVE TRIED TO FIX THIS PROPERLY ^^^^ ### see readme
export NXF_VER=24.10.0

DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -c "$PIPELINE_PATH/pipeline/ucl_myriad.config" \
    -c $CONFIG_FILE \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    -resume \
    --input $INPUT_TYPE \
    -work-dir $WORKDIR \
    ${PARAMS_FILE:+--params_file $PARAMS_FILE} # expands to nothing if PARAMS_FILE is empty, or --params_file /tmp/ephys_params_XXXX.json if it's set.
    # --debug \
    # --debug-duration 30
