#!/bin/bash

# Set default paths
SLICER_DIR_DEFAULT=~/Slicer-5.2.2-linux-amd64
DATA_DIR_DEFAULT=/home/ubuntu/data
FIBER_TRACT_MEASUREMENTS_DEFAULT=$SLICER_DIR_DEFAULT/NA-MIC/Extensions-31382/SlicerDMRI/lib/Slicer-5.2/cli-modules/FiberTractMeasurements

# Use passed arguments for paths or use defaults
SLICER_DIR=${1:-$SLICER_DIR_DEFAULT}
DATA_DIR=${2:-$DATA_DIR_DEFAULT}
FIBER_TRACT_MEASUREMENTS=${3:-$FIBER_TRACT_MEASUREMENTS_DEFAULT}

# Function to check if directory contains only VTK or VTP files
contains_only_vtk_or_vtp_files() {
    local files=("$1"/*)
    local file
    for file in "${files[@]}"; do
        if [[ -f $file && ! $file =~ \.(vtk|vtp)$ ]]; then
            return 1 # False
        fi
    done
    return 0 # True
}

# Calculate total number of subject directories for progress indication
total_dirs=$(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
current_dir=0

# Loop through each subject directory in the data directory
for subject_dir in "$DATA_DIR"/sub-*; do
    ((current_dir++))
    # Extract the subject ID from the directory name
    subject_id=$(basename "$subject_dir")

    # session directory path
    session_dir="$subject_dir/ses-baselineYear1Arm1/tractography/WhiteMatterClusters"

    start_time=$(date +%s)

    # Loop through each tract directory within the session directory
    for tract_dir in "$session_dir"/tracts_*; do
        # Check if the tract directory contains only VTK or VTP files
        if contains_only_vtk_or_vtp_files "$tract_dir"; then
            # Extract the tract name from the directory name
            tract_name=$(basename "$tract_dir")

            # Define the output file path to be in the session directory
            output_file="${session_dir}/${subject_id}_${tract_name}.csv"

            # Run the FiberTractMeasurements command with output suppression
            echo "Processing $subject_id $tract_name ($current_dir of $total_dirs)"
            "$SLICER_DIR"/Slicer --launch "$FIBER_TRACT_MEASUREMENTS" \
                --inputtype Fibers_File_Folder \
                --inputdirectory "$tract_dir" \
                --outputfile "$output_file" \
                --format Column_Hierarchy --separator Comma --moreStatistics > /dev/null 2>&1
        else
            echo "Skipping: $tract_dir contains non-VTK/VTP files or is empty"
        fi
    done

    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))


    echo "Completed $subject_id in $elapsed_time seconds"
done

echo "All subjects processed."
