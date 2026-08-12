%% CONN Setup/Import Script — multi-session (task + rest), variable TR
% -------------------------------------------------------------------
% What this script does:
%   1. Enumerates subject folders under BIDS_ROOT matching SUBJECT_GLOB
%      by resolving that wildcard ourselves via dir() (see note below),
%      then searches within each subject's own literal folder for each
%      scan TYPE separately (e.g. task-emotion run-1, task-emotion
%      run-2, rest) using conn_dir (literal glob match).
%   2. Keeps ONLY subjects who have EVERY scan type defined in scan_defs
%      AND a structural scan — anyone missing any of these is excluded
%      entirely (printed, with what they're missing) rather than given
%      a shorter session list. Prints a final manifest (subject ID +
%      matched file per scan type + structural) for the subjects that
%      remain, before anything is copied.
%   3. Sets Setup.RT = NaN, so CONN reads the TR for EACH SESSION from
%      that file's BIDS sidecar .json (RepetitionTime field) instead of
%      assuming one fixed TR for everyone. This is what lets task and
%      resting-state scans have different TRs.
%   4. Sets Setup.localcopy = true, so CONN COPIES the raw files into
%      the local CONN project data folder instead of referencing them
%      in place inside your BIDS directory. Your BIDS directory is
%      never written to.
%   5. Sets Setup.done = 0, so this ONLY defines subjects/sessions/data
%      — it does NOT run preprocessing, denoising, or any analysis.
%
% IMPORTANT: this script assumes every subject's functional .nii.gz
% file has a matching .json sidecar in the same folder (standard BIDS).
% If any are missing, set MANUAL_TR below to fall back on fixed values.
%
% NOTE ON conn_dir AND WILDCARDS: conn_dir only expands a wildcard in
% the FINAL path component (the filename); it does NOT expand wildcards
% in intermediate directory segments (e.g. 'sub-MGHL2*') — it returns
% that segment back literally, unresolved, for every match. Passing a
% pattern like fullfile(BIDS_ROOT,'sub-MGHL2*','ses-001','func','*bold.nii.gz')
% directly to conn_dir therefore returns paths that still contain the
% literal characters "sub-MGHL2*", which (a) breaks subject-ID parsing,
% since every file appears to come from the same "subject", and (b) are
% not valid filesystem paths, which would break the later file copy.
% To avoid this, we resolve the subject-level wildcard ourselves first
% with dir(), then call conn_dir separately per subject, scoped to that
% subject's already-resolved (literal, non-wildcarded) folder — leaving
% only the filename to be resolved by conn_dir, which it does correctly.
% -------------------------------------------------------------------
addpath('/autofs/space/nicc_003/users/holly/repo/spm12')
addpath('/autofs/space/nicc_003/users/holly/repo/conn_25b')

clear batch;

%% ------------------- USER SETTINGS (edit these) -------------------

BIDS_ROOT    = '/autofs/space/nicc_006/data/LETBI/BIDS';                   % <-- root of your BIDS dataset (contains sub-* folders)
PROJECT_DIR  = '/autofs/space/nicc_006/data/LETBI/BIDS/derivatives/conn_v25b';          % <-- folder where the NEW conn project will be created
PROJECT_NAME = 'MGHL2_emotion_rest';                           % <-- project name, no spaces (creates PROJECT_NAME.mat)

% Set to true only if some/all of your sidecar .json files are missing
% and CONN can't auto-read RepetitionTime. If true, define MANUAL_TR
% values per scan type below and the script will use those instead.
USE_MANUAL_TR = false;
%MANUAL_TR.task = 1.5;   % example only — used only if USE_MANUAL_TR = true
%MANUAL_TR.rest = 2.0;   % example only — used only if USE_MANUAL_TR = true

% ---- Wildcard used to enumerate subject folders directly under BIDS_ROOT ----
SUBJECT_GLOB = 'sub-MGHL2*';

% Real subject IDs (as printed in the manifest/subject-ID map, e.g.
% 'MGHL2p013') to exclude by hand — e.g. known-bad data, failed the
% GZIP integrity check, or implausible scan content (wrong frame count,
% etc.) that isn't a matter of tightening the patterns above. Excluded
% here, before any file searching happens for them.
EXCLUDE_SUBJECTS = {};   % example: {'MGHL2p013', 'MGHL2p031'}

% ---- Define one glob pattern PER SCAN TYPE, RELATIVE TO EACH SUBJECT'S FOLDER ----
% Adjust these to your actual BIDS naming. Check one real filename
% first, e.g. sub-MGHL2p001_ses-001_task-emotion_run-01_bold.nii.gz
% Order in this list = session order CONN will assign (see below).
% Do not put subject-level wildcards here — see the NOTE ON conn_dir above.
scan_defs = struct( ...
    'label',   {'task_emotion_run1', 'task_emotion_run2', 'rest_run1'}, ...
    'relpath', { ...
        fullfile('ses-001', 'func', '*task-emotion_run-01_bold.nii.gz'), ...
        fullfile('ses-001', 'func', '*task-emotion_run-02_bold.nii.gz'), ...
        fullfile('ses-001', 'func', '*task-rest_bold.nii.gz') ...
    }, ...
    'type',    {'task','task','rest'} ...   % used only if USE_MANUAL_TR = true
    );

% Structural file pattern, relative to each subject's folder — set to '' to skip structural import
STRUCT_RELPATH = fullfile('ses-001', 'anat', '*ses-001_T1w.nii.gz');

%% ------------------- ENUMERATE SUBJECT FOLDERS -------------------
% Resolve the subject-level wildcard ourselves (dir() expands it
% correctly), rather than handing it to conn_dir. See NOTE above.

subj_listing = dir(fullfile(BIDS_ROOT, SUBJECT_GLOB));
subj_listing = subj_listing([subj_listing.isdir]);
subj_folder_names = {subj_listing.name};

subj_tokens = regexp(subj_folder_names, 'sub-([A-Za-z0-9]+)', 'tokens', 'once');
if any(cellfun(@isempty, subj_tokens))
    error('Could not parse a subject ID from a matched folder name. Check SUBJECT_GLOB:\n  %s', fullfile(BIDS_ROOT, SUBJECT_GLOB));
end
all_subjects = cellfun(@(x) x{1}, subj_tokens, 'UniformOutput', false);
[all_subjects, sort_idx] = sort(all_subjects);
subj_folder_names = subj_folder_names(sort_idx);
nsubjects = numel(all_subjects);

fprintf('Found %d subject folder(s) matching "%s".\n', nsubjects, SUBJECT_GLOB);

%% ------------------- APPLY MANUAL SUBJECT EXCLUSIONS -------------------

if ~isempty(EXCLUDE_SUBJECTS)
    is_excluded = ismember(all_subjects, EXCLUDE_SUBJECTS);
    if any(is_excluded)
        fprintf('Manually excluding %d subject(s) via EXCLUDE_SUBJECTS: %s\n', sum(is_excluded), strjoin(all_subjects(is_excluded), ', '));
    end
    unmatched = setdiff(EXCLUDE_SUBJECTS, all_subjects);
    if ~isempty(unmatched)
        warning('EXCLUDE_SUBJECTS contains ID(s) not found among matched subject folders: %s', strjoin(unmatched, ', '));
    end
    all_subjects       = all_subjects(~is_excluded);
    subj_folder_names  = subj_folder_names(~is_excluded);
    nsubjects          = numel(all_subjects);
end

%% ------------------- FIND FILES FOR EACH SCAN TYPE, PER SUBJECT -------------------
% conn_dir is now called once per subject per scan type, scoped to that
% subject's already-resolved literal folder, so the only wildcard left
% for it to expand is in the filename — which it does correctly.

nscantypes = numel(scan_defs);
for k = 1:nscantypes
    scan_defs(k).files = cell(nsubjects, 1);   % scan_defs(k).files{nsub} = matched file, or '' if none
end

do_structural = ~isempty(STRUCT_RELPATH);
struct_files = cell(nsubjects, 1);

for nsub = 1:nsubjects
    subj_dir = fullfile(BIDS_ROOT, subj_folder_names{nsub});

    for k = 1:nscantypes
        matches = cellstr(conn_dir(fullfile(subj_dir, scan_defs(k).relpath)));
        matches = matches(~cellfun(@isempty, matches));
        if numel(matches) > 1
            fprintf('\nScan type "%s" matched more than one file for subject %s:\n', scan_defs(k).label, all_subjects{nsub});
            fprintf('  %s\n', matches{:});
            error('Scan type "%s" matched more than one file for subject %s. Tighten the pattern (see file list printed above).', scan_defs(k).label, all_subjects{nsub});
        elseif ~isempty(matches)
            scan_defs(k).files{nsub} = matches{1};
        end
    end

    if do_structural
        smatches = cellstr(conn_dir(fullfile(subj_dir, STRUCT_RELPATH)));
        smatches = smatches(~cellfun(@isempty, smatches));
        if numel(smatches) > 1
            error('STRUCT_RELPATH matched more than one file for subject %s:\n  %s', all_subjects{nsub}, strjoin(smatches, sprintf('\n  ')));
        elseif ~isempty(smatches)
            struct_files{nsub} = smatches{1};
        end
    end
end

for k = 1:nscantypes
    fprintf('Scan type "%-18s": %d file(s) found\n', scan_defs(k).label, sum(~cellfun(@isempty, scan_defs(k).files)));
end

%% ------------------- FILTER TO COMPLETE SUBJECTS ONLY -------------------
% Only subjects with EVERY scan type in scan_defs AND a structural scan
% (when STRUCT_RELPATH is set) are kept. Anyone missing any of these is
% excluded entirely — no partial-session subjects are carried forward.

is_complete = true(nsubjects, 1);
for nsub = 1:nsubjects
    for k = 1:nscantypes
        if isempty(scan_defs(k).files{nsub})
            is_complete(nsub) = false;
        end
    end
    if do_structural && isempty(struct_files{nsub})
        is_complete(nsub) = false;
    end
end

if any(~is_complete)
    fprintf('\nExcluding %d subject(s) missing one or more required scans:\n', sum(~is_complete));
    excl_idx = find(~is_complete)';
    for nsub = excl_idx
        missing = {};
        for k = 1:nscantypes
            if isempty(scan_defs(k).files{nsub})
                missing{end+1} = scan_defs(k).label; %#ok<AGROW>
            end
        end
        if do_structural && isempty(struct_files{nsub})
            missing{end+1} = 'structural'; %#ok<AGROW>
        end
        fprintf('  %-12s : missing %s\n', all_subjects{nsub}, strjoin(missing, ', '));
    end
end

all_subjects = all_subjects(is_complete);
for k = 1:nscantypes
    scan_defs(k).files = scan_defs(k).files(is_complete);
end
struct_files = struct_files(is_complete);
nsubjects    = numel(all_subjects);

% Final clean manifest — subject ID plus the exact file matched for each
% required scan type and structural. This is the list actually used to
% build the CONN project; verify it before anything gets copied.
fprintf('\n%d subject(s) have complete data and will be included:\n', nsubjects);
for nsub = 1:nsubjects
    fprintf('\n  %s\n', all_subjects{nsub});
    for k = 1:nscantypes
        fprintf('    %-18s : %s\n', scan_defs(k).label, scan_defs(k).files{nsub});
    end
    if do_structural
        fprintf('    %-18s : %s\n', 'structural', struct_files{nsub});
    end
end

%% ------------------- WRITE CONN SUBJECT-ID <-> REAL SUBJECT-ID MAP -------------------
% CONN refers to subjects internally as sub-0001, sub-0002, ... in batch
% order (the order of all_subjects here) — that's what shows up in the
% copied data folder structure and in CONN's own error messages (e.g.
% "sub-0008"). This file lets you look up which real subject a given
% internal ID corresponds to.

if ~exist(PROJECT_DIR, 'dir'); mkdir(PROJECT_DIR); end
subject_map_file = fullfile(PROJECT_DIR, [PROJECT_NAME '_subject_id_map.csv']);
fid = fopen(subject_map_file, 'w');
if fid == -1
    error('Could not open subject ID map file for writing:\n  %s', subject_map_file);
end
fprintf(fid, 'conn_subject_id,real_subject_id\n');
for nsub = 1:nsubjects
    fprintf(fid, 'sub-%04d,%s\n', nsub, all_subjects{nsub});
end
fclose(fid);
fprintf('\nWrote CONN subject-ID map to:\n  %s\n', subject_map_file);

%% ------------------- PRE-FLIGHT: VERIFY GZIP INTEGRITY -------------------
% Catches corrupt/mislabeled .nii.gz files (wrong magic bytes) BEFORE
% conn_batch starts copying, so a bad file surfaces with its real BIDS
% path instead of a cryptic error deep inside CONN's copy step after
% other subjects have already been (wastefully) copied.

bad_files = {};
for k = 1:nscantypes
    for nsub = 1:nsubjects
        f = scan_defs(k).files{nsub};
        if endsWith(f, '.gz') && ~is_valid_gzip(f)
            bad_files{end+1} = f; %#ok<AGROW>
        end
    end
end
if do_structural
    for nsub = 1:nsubjects
        f = struct_files{nsub};
        if endsWith(f, '.gz') && ~is_valid_gzip(f)
            bad_files{end+1} = f; %#ok<AGROW>
        end
    end
end
if ~isempty(bad_files)
    fprintf('\nThe following file(s) are named .gz but are not valid GZIP data:\n');
    fprintf('  %s\n', bad_files{:});
    error('%d file(s) failed GZIP validation (see list above). Fix or exclude these before continuing.', numel(bad_files));
end
fprintf('All matched .gz files passed GZIP integrity check.\n');

%% ------------------- BUILD PER-SUBJECT SESSION LISTS -------------------
% All remaining subjects have every scan type in scan_defs, in the fixed
% order defined there, so every subject gets the same session count.

session_map = cell(nsubjects, 1);   % session_map{nsub} = cell array of scan_defs labels, in session order
for nsub = 1:nsubjects
    labels_here = {scan_defs.label};
    files_here  = cell(1, nscantypes);
    for k = 1:nscantypes
        files_here{k} = scan_defs(k).files{nsub};
    end
    session_map{nsub} = labels_here;
    batch.Setup.functionals{nsub} = files_here;  % Setup.functionals{nsub}{nses}
end

%% ------------------- STRUCTURAL PER SUBJECT -------------------

if do_structural
    for nsub = 1:nsubjects
        batch.Setup.structurals{nsub} = struct_files{nsub};
    end
end

%% ------------------- TR HANDLING -------------------

if USE_MANUAL_TR
    % Manual fallback: builds a per-subject/per-session TR using scan
    % type ('task' vs 'rest') to look up MANUAL_TR. Only used if your
    % .json sidecars are missing/unreliable.
    for nsub = 1:nsubjects
        for nses = 1:numel(session_map{nsub})
            lbl = session_map{nsub}{nses};
            k = find(strcmp({scan_defs.label}, lbl));
            batch.Setup.RT(nsub, nses) = MANUAL_TR.(scan_defs(k).type); %#ok<AGROW>
        end
    end
else
    % Preferred: let CONN read RepetitionTime from each session's BIDS
    % .json sidecar automatically (handles differing TR across task vs
    % rest, or across runs, with no manual bookkeeping).
    batch.Setup.RT = NaN;
end

%% ------------------- BUILD REMAINING CONN BATCH FIELDS -------------------

batch.filename = fullfile(PROJECT_DIR, [PROJECT_NAME '.mat']);

batch.Setup.isnew     = 1;
batch.Setup.nsubjects = nsubjects;

% Copies raw files into the CONN project's local data folder instead of
% referencing them in place inside BIDS_ROOT. Your BIDS directory is
% never modified.
batch.Setup.localcopy = true;

% done = 0 --> ONLY defines/imports Setup info (subjects, sessions,
% functional/structural data). Does NOT run preprocessing, denoising,
% or any analysis steps.
batch.Setup.done      = 0;
batch.Setup.overwrite = 0;

%% ------------------- RUN (Setup + import only) -------------------

conn_batch(batch);

fprintf('\nDone. CONN project created with %d subject(s):\n  %s\n', nsubjects, batch.filename);
fprintf('Functional (and structural, if matched) files were COPIED into the local CONN project data folder.\n');
if ~USE_MANUAL_TR
    fprintf('TR will be read automatically per-session from BIDS .json sidecars.\n');
end
fprintf('No preprocessing, denoising, or analysis was run — open the project in the CONN GUI to continue.\n');

%% ------------------- LOCAL FUNCTIONS -------------------

function tf = is_valid_gzip(filename)
% Checks the first 2 bytes for the GZIP magic number (0x1f 0x8b) rather
% than trusting the .gz extension, so a mislabeled/corrupt file is
% caught here instead of failing deep inside conn_batch's unzip step.
fid = fopen(filename, 'r');
if fid == -1
    tf = false;
    return;
end
magic = fread(fid, 2, 'uint8=>uint8');
fclose(fid);
tf = numel(magic) == 2 && magic(1) == 31 && magic(2) == 139;
end
