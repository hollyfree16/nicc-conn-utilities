#!/usr/bin/env python3
"""
Loop through a BIDS directory and print TR and number of frames
for task-rest_bold scans in each subject's func folder.

Usage:
    python bids_rest_bold_info.py /path/to/bids_dir
    python bids_rest_bold_info.py /path/to/bids_dir --site UWp
    python bids_rest_bold_info.py /path/to/bids_dir --site UWp --site BOS
    python bids_rest_bold_info.py /path/to/bids_dir --all-sites

Requires:
    pip install nibabel
"""

import sys
import json
import argparse
from collections import Counter
from pathlib import Path

try:
    import nibabel as nib
except ImportError:
    sys.exit("This script requires nibabel. Install it with: pip install nibabel")


def get_tr_and_frames(nii_path: Path):
    """Return (TR, n_frames) for a NIfTI file, preferring the JSON sidecar for TR."""
    img = nib.load(str(nii_path))
    shape = img.shape
    n_frames = shape[3] if len(shape) >= 4 else 1

    # Prefer RepetitionTime from the JSON sidecar (BIDS standard, in seconds)
    json_path = nii_path
    # Strip .nii.gz or .nii to get the base, then add .json
    if json_path.name.endswith(".nii.gz"):
        json_path = json_path.with_name(json_path.name[:-7] + ".json")
    else:
        json_path = json_path.with_suffix(".json")

    tr = None
    if json_path.exists():
        try:
            with open(json_path) as f:
                meta = json.load(f)
            tr = meta.get("RepetitionTime")
        except (json.JSONDecodeError, OSError):
            tr = None

    # Fall back to the NIfTI header if no sidecar value found
    if tr is None:
        tr = float(img.header.get_zooms()[3]) if len(img.header.get_zooms()) >= 4 else None

    return tr, n_frames


def main(bids_dir: str, sites, all_sites: bool, filter_matching: bool, tr_filter: float, frames_filter: int):
    bids_path = Path(bids_dir)
    if not bids_path.is_dir():
        sys.exit(f"Not a directory: {bids_dir}")

    if all_sites:
        subjects = sorted(bids_path.glob("sub-*"))
        if not subjects:
            print(f"No sub-* directories found in {bids_dir}")
            return
    else:
        # Match sub-<SITE>* for each requested site prefix, e.g. sub-UWp*
        subjects = []
        for site in sites:
            matches = sorted(bids_path.glob(f"sub-{site}*"))
            if not matches:
                print(f"Warning: no sub-{site}* directories found")
            subjects.extend(matches)
        subjects = sorted(set(subjects))
        if not subjects:
            print(f"No matching subject directories found in {bids_dir}")
            return

    results = []

    for sub_dir in subjects:
        sub_id = sub_dir.name

        # Sessions may or may not exist
        ses_dirs = sorted(sub_dir.glob("ses-*"))
        if ses_dirs:
            search_roots = [(ses_dir.name, ses_dir / "func") for ses_dir in ses_dirs]
        else:
            search_roots = [(None, sub_dir / "func")]

        for ses_id, func_dir in search_roots:
            if not func_dir.is_dir():
                continue

            # Handles both single-run (task-rest_bold.nii.gz) and
            # multi-run (run-01_task-rest_bold.nii.gz) naming
            bold_files = sorted(func_dir.glob("*task-rest_bold.nii.gz"))

            for bold_file in bold_files:
                tr, n_frames = get_tr_and_frames(bold_file)
                results.append({
                    "sub": sub_id,
                    "ses": ses_id if ses_id else "n/a",
                    "run": bold_file.name,
                    "tr": tr,
                    "frames": n_frames,
                })

    if not results:
        print("No task-rest_bold scans found.")
        return

    excluded = []
    if filter_matching or tr_filter is not None or frames_filter is not None:
        if tr_filter is not None and frames_filter is not None:
            target_tr, target_frames = tr_filter, frames_filter
        else:
            # Auto-detect the most common (TR, frames) combo among known-TR runs
            combo_counts = Counter(
                (round(r["tr"], 3), r["frames"]) for r in results if r["tr"] is not None
            )
            if not combo_counts:
                print("Cannot filter: no scans have a known TR.")
                return
            target_tr, target_frames = combo_counts.most_common(1)[0][0]

        matching, excluded = [], []
        for r in results:
            if r["tr"] is not None and round(r["tr"], 3) == round(target_tr, 3) and r["frames"] == target_frames:
                matching.append(r)
            else:
                excluded.append(r)
        results = matching
        print(f"Filtering to TR={target_tr}s, frames={target_frames} ({len(results)} matching runs, {len(excluded)} excluded)\n")

    for r in results:
        tr_str = f"{r['tr']}s" if r["tr"] is not None else "unknown"
        print(f"subject-id {r['sub']} | session {r['ses']} | run {r['run']} | TR {tr_str} | # of frames {r['frames']}")

    if excluded:
        print(f"\nExcluded {len(excluded)} run(s) with mismatched TR/frames:")
        for r in excluded:
            tr_str = f"{r['tr']}s" if r["tr"] is not None else "unknown"
            print(f"  subject-id {r['sub']} | session {r['ses']} | run {r['run']} | TR {tr_str} | # of frames {r['frames']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Print TR and frame count for task-rest_bold scans in a BIDS directory."
    )
    parser.add_argument("bids_dir", help="Path to the BIDS directory")
    parser.add_argument(
        "--site",
        action="append",
        default=[],
        metavar="PREFIX",
        help="Site prefix to filter subjects by, e.g. --site UWp matches sub-UWp*. "
             "Can be passed multiple times to include several sites. "
             "Defaults to UWp if neither --site nor --all-sites is given.",
    )
    parser.add_argument(
        "--all-sites",
        action="store_true",
        help="Include all subjects (sub-*) regardless of site prefix.",
    )
    parser.add_argument(
        "--filter-matching",
        action="store_true",
        help="Only show runs matching the most common (TR, # of frames) combo found; "
             "runs that don't match are listed separately as excluded.",
    )
    parser.add_argument(
        "--tr",
        type=float,
        default=None,
        metavar="SECONDS",
        help="Only show runs with this exact TR (seconds). Must be paired with --frames.",
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=None,
        metavar="N",
        help="Only show runs with exactly this many frames. Must be paired with --tr.",
    )
    args = parser.parse_args()

    if (args.tr is None) != (args.frames is None):
        parser.error("--tr and --frames must be given together.")

    sites = args.site if args.site else (["UWp"] if not args.all_sites else [])
    main(args.bids_dir, sites, args.all_sites, args.filter_matching, args.tr, args.frames)