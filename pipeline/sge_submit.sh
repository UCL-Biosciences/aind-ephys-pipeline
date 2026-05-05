# !/bin/bash
#$ -S /bin/bash
#$ -l mem=4G # 4
#$ -l h_rt=24:00:00 # 24
#$ -cwd
#$ -j y
#$ -N nextflow_aind_ephys
#$ -m be # email to be notified when the job begins and ends

USE_DATA=OPEN_EPHYS # can be NWB_SYNTHETIC, SHORT_SPIKEGLX, or others

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
else
    echo "Unknown data type: $USE_DATA"
    exit 1
fi

# Now redirect log with variable available
# (note the first part checks if the script is running interactively, and only redirects if it's not. Otherwise interactive session get stuck)
[[ $- != *i* ]] && exec &>> /home/ucsagil/Scratch/projects/ephys/logs/nextflow_aind_ephys_${JOB_ID}_${INPUT_TYPE}.log

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
sed -i 's/"load_sync_timestamps": true/"load_sync_timestamps": false/' /home/ucsagil/Scratch/projects/ephys/workdir/58/581124*/capsule/data/job*.json

DATA_PATH=$DATA_PATH RESULTS_PATH=$RESULTS_PATH nextflow \
    -C "$PIPELINE_PATH/pipeline/ucl_myriad.config" \
    -C $CONFIG_FILE \
    -log $RESULTS_PATH/nextflow/nextflow.log \
    run -resume $PIPELINE_PATH/pipeline/main_multi_backend.nf \
    --input $INPUT_TYPE \
    -work-dir $WORKDIR 
    # --debug \
    # --debug-duration 30
