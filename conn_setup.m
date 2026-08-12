%% CONN Setup/Import Script — multi-session (task + rest), variable TR
% -------------------------------------------------------------------
% What this script does:
%   1. Enumerates subject folders under BIDS_ROOT matching SUBJECT_GLOB
%      by resolving that wildcard ourselves via dir() (see note below),
%      then searches within each subject's own literal folder for each
%      scan TYPE separately (e.g. task-emotion run-1, task-emotion
%      run-2, rest) using conn_dir (literal glob match).
%   2. For each subject, assembles whichever sessions actually exist
%      for them, in a fixed, documented order — subjects with fewer
%      sessions (e.g. only 1 resting scan) are simply given a shorter
%      list; CONN infers nsessions per-subject from that list length.
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

%% ------------------- BUILD PER-SUBJECT SESSION LISTS -------------------
% For each subject, include whichever scan types they actually have,
% IN THE ORDER DEFINED IN scan_defs (so session order is consistent
% and documented across subjects, even when some sessions are missing).

session_map = cell(nsubjects, 1);   % session_map{nsub} = cell array of scan_defs labels, in session order
for nsub = 1:nsubjects
    labels_here = {};
    files_here  = {};
    for k = 1:nscantypes
        if ~isempty(scan_defs(k).files{nsub})
            labels_here{end+1} = scan_defs(k).label;          %#ok<AGROW>
            files_here{end+1}  = scan_defs(k).files{nsub};     %#ok<AGROW>
        end
    end
    if isempty(files_here)
        warning('Subject %s matched no scan types — skipping.', all_subjects{nsub});
    end
    session_map{nsub} = labels_here;
    batch.Setup.functionals{nsub} = files_here;  % Setup.functionals{nsub}{nses}
end

% Print a per-subject summary so you can verify session assignment
% before anything gets copied.
fprintf('\nPer-subject session assignment:\n');
for nsub = 1:nsubjects
    fprintf('  %-12s : %s\n', all_subjects{nsub}, strjoin(session_map{nsub}, ', '));
end

%% ------------------- STRUCTURAL PER SUBJECT -------------------

if do_structural
    for nsub = 1:nsubjects
        if ~isempty(struct_files{nsub})
            batch.Setup.structurals{nsub} = struct_files{nsub};
        else
            warning('No structural file found for subject %s — leaving structural unset.', all_subjects{nsub});
        end
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

if ~exist(PROJECT_DIR, 'dir'); mkdir(PROJECT_DIR); end
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
