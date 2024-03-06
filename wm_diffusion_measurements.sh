#!/bin/bash

# Set default values
SLICER_DIR_DEFAULT=~/Slicer-5.2.2-linux-amd64
LOCAL_DATA_DIR_DEFAULT=/home/ubuntu/data
CSV_ROOT_DIR_DEFAULT=/home/ubuntu/wm_diffusion_measurements/CSVFILES
FIBER_TRACT_MEASUREMENTS_DEFAULT="$SLICER_DIR_DEFAULT/NA-MIC/Extensions-31382/SlicerDMRI/lib/Slicer-5.2/cli-modules/FiberTractMeasurements"
S3_BUCKET_NAME_DEFAULT="nda-enclave-c3371"
S3_DATA_DIR_DEFAULT="abcdRelease3_dMRIHarmonized/Derivatives"
CASELIST_DEFAULT="/home/ubuntu/wm_diffusion_measurements/sub_test.txt"
LOGFILE_DEFAULT="/home/ubuntu/wm_diffusion_measurements/wm_diffusion_measurements.log"

# Parse command line options
while getopts ":s:r:v:f:b:d:c:l:" opt; do
  case ${opt} in
    s ) SLICER_DIR=$OPTARG ;;
    r ) LOCAL_DATA_DIR=$OPTARG ;;
    v ) CSV_ROOT_DIR=$OPTARG ;;
    f ) FIBER_TRACT_MEASUREMENTS=$OPTARG ;;
    b ) S3_BUCKET_NAME=$OPTARG ;;
    d ) S3_DATA_DIR=$OPTARG ;;
    c ) CASELIST=$OPTARG ;;
    l ) LOGFILE=$OPTARG ;;
    \? ) echo "Usage: cmd [-s slicer_dir] [-r local_data_dir] [-v csv_root_dir]  [-f fiber_tract_measurements] [-b s3_bucket_name] [-d s3_data_dir] [-c caselist] [-l logfile]"
         exit 1 ;;
  esac
done

# Use default values if not set
SLICER_DIR=${SLICER_DIR:-$SLICER_DIR_DEFAULT}
LOCAL_DATA_DIR=${LOCAL_DATA_DIR:-$LOCAL_DATA_DIR_DEFAULT}
CSV_ROOT_DIR=${CSV_ROOT_DIR:-$CSV_ROOT_DIR_DEFAULT}
FIBER_TRACT_MEASUREMENTS=${FIBER_TRACT_MEASUREMENTS:-$FIBER_TRACT_MEASUREMENTS_DEFAULT}
S3_BUCKET_NAME=${S3_BUCKET_NAME:-$S3_BUCKET_NAME_DEFAULT}
S3_DATA_DIR=${S3_DATA_DIR:-$S3_DATA_DIR_DEFAULT}
CASELIST=${CASELIST:-$CASELIST_DEFAULT}
LOGFILE=${LOGFILE:-$LOGFILE_DEFAULT}

# Ensure local data directory exists
mkdir -p "$LOCAL_DATA_DIR"

# Function to log messages; writes to both terminal and logfile if specified
log_message() {
  if [ -n "$LOGFILE" ]; then
    echo "$@" | tee -a "$LOGFILE"
  else
    echo "$@"
  fi
}

export SLICER_DIR FIBER_TRACT_MEASUREMENTS LOCAL_DATA_DIR S3_BUCKET_NAME S3_DATA_DIR CSV_ROOT_DIR

start_date_time=$(date)
log_message "Script started at: $start_date_time"

# Define the function for processing each subject
process_subject() {
    subject_id=$1
    start_time=$(date +%s)
    log_message "Processing $subject_id"

    # Define tract directories to sync
    tract_directories=("tracts_commissural" "tracts_left_hemisphere" "tracts_right_hemisphere")
    session_dir_path="$S3_DATA_DIR/$subject_id/ses-baselineYear1Arm1/tractography/WhiteMatterClusters"

    # Sync each required tract directory
    for tract_dir in "${tract_directories[@]}"; do
        aws s3 sync "s3://$S3_BUCKET_NAME/$session_dir_path/$tract_dir" "$LOCAL_DATA_DIR/$subject_id/ses-baselineYear1Arm1/tractography/WhiteMatterClusters/$tract_dir/" > /dev/null 2>&1
    done

    # Process each tract directory
    local_session_dir="$LOCAL_DATA_DIR/$subject_id/ses-baselineYear1Arm1/tractography/WhiteMatterClusters"

    # Before processing, move any non-VTK/VTP (or non-directory) files back one directory
    find "$local_session_dir" -mindepth 2 -type f ! -name "*.vtk" ! -name "*.vtp" -exec mv -t "$local_session_dir" {} +

    for tract_dir in "${tract_directories[@]}"; do
        if [ "$(ls -A $local_session_dir/$tract_dir)" ]; then
            output_file="$local_session_dir/${subject_id}_${tract_dir}.csv"
            echo "Generating CSV for $subject_id $tract_dir"
            "$SLICER_DIR"/Slicer --launch "$FIBER_TRACT_MEASUREMENTS" \
                --inputtype Fibers_File_Folder \
                --inputdirectory "$local_session_dir/$tract_dir" \
                --outputfile "$output_file" \
                --format Column_Hierarchy --separator Comma --moreStatistics > /dev/null 2>&1
        else
            echo "Skipping empty directory: $tract_dir"
        fi
    done

    # Sync processed CSV files back to S3
    for tract_dir in "${tract_directories[@]}"; do
        aws s3 cp "$local_session_dir/${subject_id}_${tract_dir}.csv" "s3://$S3_BUCKET_NAME/$session_dir_path/" > /dev/null 2>&1
    done

    # Copy each CSV file to the CSV root directory
    echo "CSV_ROOT_DIR is set to: $CSV_ROOT_DIR" # Debugging output
    for tract_dir in "${tract_directories[@]}"; do
        csv_file="$local_session_dir/${subject_id}_${tract_dir}.csv"
        if [ -f "$csv_file" ]; then
            cp "$csv_file" "$CSV_ROOT_DIR/" || echo "Failed to copy $csv_file to $CSV_ROOT_DIR"
        fi
    done

    # Cleanup local data
#     rm -rf "$LOCAL_DATA_DIR/$subject_id"

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    log_message "Elapsed time for $subject_id: $elapsed_time seconds"

}

if [ -n "$LOGFILE" ]; then
    exec > >(tee -a "$LOGFILE") 2>&1
fi

overall_start_time=$(date +%s)

export -f process_subject log_message

# Read subjects from the caselist
mapfile -t subjects < "$CASELIST"

# Process subjects in parallel
parallel -j 4 process_subject ::: "${subjects[@]}"

overall_end_time=$(date +%s)
log_message "Start time: $overall_start_time, End time: $overall_end_time"
overall_elapsed_time=$((overall_end_time - overall_start_time))

log_message "Elapsed time for all subjects: $overall_elapsed_time seconds"

# Print end date and time
end_date_time=$(date)
log_message "Script ended at: $end_date_time"