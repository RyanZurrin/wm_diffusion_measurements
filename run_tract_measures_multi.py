#!/usr/bin/env python3

import argparse
import subprocess
from pathlib import Path
from s3path import S3Path

def is_valid_tract_directory(tract_directory):
    """Check if S3 tract directory is not empty and contains only VTK or VTP files."""
    has_files = False
    for item in tract_directory.iterdir():
        if item.is_file():
            has_files = True
            if not item.name.endswith(('.vtk', '.vtp')):
                return False  # Contains a file that is not VTK or VTP
    return has_files  # True if non-empty and all files are VTK or VTP, False otherwise

def main(args):
    subjects_path = S3Path(f"s3://{args.bucket_name}/{args.subjects_path}")
    slicer_dir = Path(args.slicer_dir).expanduser()

    for subject_dir in subjects_path.iterdir():
        if subject_dir.is_dir():
            # Define tract directories
            tract_directories = [
                subject_dir / "ses-baselineYear1Arm1/tractography/WhiteMatterClusters/tracts_commissural",
                subject_dir / "ses-baselineYear1Arm1/tractography/WhiteMatterClusters/tracts_left_hemisphere",
                subject_dir / "ses-baselineYear1Arm1/tractography/WhiteMatterClusters/tracts_right_hemisphere",
            ]
            
            for tract_dir in tract_directories:
                if is_valid_tract_directory(tract_dir):
                    output_file = f"{tract_dir}/{subject_dir.name}_{tract_dir.name}.csv"
                    # Adjust the subprocess call to use the actual command you need
                    subprocess.run([
                        str(slicer_dir / "Slicer"),
                        "--launch", str(args.fiber_tract_measurements),
                        "--inputtype", "Fibers_File_Folder",
                        "--inputdirectory", str(tract_dir),
                        "--outputfile", output_file,
                        "--format", "Column_Hierarchy",
                        "--separator", "Comma",
                        "--moreStatistics"
                    ])
                    print(f"Processed {tract_dir}")
                else:
                    print(f"Skipping: {tract_dir} contains non-VTK/VTP files or is empty")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Automate tract measurements using Slicer with data on AWS S3.")
    parser.add_argument("--bucket_name", required=True, help="Name of the S3 bucket containing the data.")
    parser.add_argument("--subjects_path", required=True, help="Path within the S3 bucket to the subject directories.")
    parser.add_argument("--slicer_dir", default="~/Slicer-5.2.2-linux-amd64",
                        help="Path to the Slicer installation directory. Default: '~/Slicer-5.2.2-linux-amd64'")
    parser.add_argument("--fiber_tract_measurements", required=True,
                        help="Path to the FiberTractMeasurements CLI module.")

    args = parser.parse_args()

    main(args)
