#!/usr/bin/env python3

import os
import re
import argparse
import subprocess
from pathlib import Path

def is_valid_tract_directory(directory):
    """Check if directory is not empty and contains only VTK or VTP files."""
    has_files = False
    for item in directory.iterdir():
        if item.is_file():
            has_files = True
            if not re.search(r'\.(vtk|vtp)$', item.name):
                return False  # Contains a file that is not VTK or VTP
    return has_files  # True if non-empty and all files are VTK or VTP, False otherwise


def main(args):
    slicer_dir = Path(args.slicer_dir)
    data_dir = Path(args.data_dir)
    fiber_tract_measurements = Path(args.fiber_tract_measurements)
    
    total_dirs = sum(1 for _ in data_dir.iterdir())
    current_dir = 0

    for subject_dir in data_dir.glob("sub-*"):
        current_dir += 1
        session_dir = subject_dir / "ses-baselineYear1Arm1/tractography/WhiteMatterClusters"
        
        for tract_dir in session_dir.glob("tracts_*"):
            if is_valid_tract_directory(tract_dir):
                tract_name = tract_dir.name
                output_file = session_dir / f"{subject_dir.name}_{tract_name}.csv"
                
                print(f"Processing {subject_dir.name} {tract_name} ({current_dir} of {total_dirs})")
                
                subprocess.run([
                    str(slicer_dir / "Slicer"),
                    "--launch", str(fiber_tract_measurements),
                    "--inputtype", "Fibers_File_Folder",
                    "--inputdirectory", str(tract_dir),
                    "--outputfile", str(output_file),
                    "--format", "Column_Hierarchy",
                    "--separator", "Comma",
                    "--moreStatistics"
                ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                print(f"Skipping: {tract_dir} contains non-VTK/VTP files or is empty")
                
        print(f"Completed {current_dir} of {total_dirs} subjects.")
        
    print("All subjects processed.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Automate tract measurements using Slicer.")
    parser.add_argument("--slicer_dir", default="~/Slicer-5.2.2-linux-amd64",
                        help="Path to the Slicer installation directory. Default: '~/Slicer-5.2.2-linux-amd64'")
    parser.add_argument("--data_dir", default="/home/ubuntu/data",
                        help="Path to the data directory. Default: '/home/ubuntu/data'")
    parser.add_argument("--fiber_tract_measurements", default=None,
                        help="Path to the FiberTractMeasurements CLI module. If not specified, assumes default location within slicer_dir.")

    args = parser.parse_args()

    # Ensure paths are fully expanded
    args.slicer_dir = str(Path(args.slicer_dir).expanduser())
    args.data_dir = str(Path(args.data_dir).expanduser())

    # If fiber_tract_measurements path is not specified, derive it from slicer_dir
    if args.fiber_tract_measurements is None:
        args.fiber_tract_measurements = os.path.join(args.slicer_dir, "NA-MIC/Extensions-31382/SlicerDMRI/lib/Slicer-5.2/cli-modules/FiberTractMeasurements")
    else:
        args.fiber_tract_measurements = str(Path(args.fiber_tract_measurements).expanduser())

    main(args)

