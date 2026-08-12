%% CONN Setup/Import Script — multi-session (task + rest), variable TR
% -------------------------------------------------------------------
% What this script does:
%   1. Searches your BIDS dataset for each scan TYPE separately (e.g.
%      task-emotion run-1, task-emotion run-2, rest run-1, rest run-2)
%      using conn_dir (literal glob match).
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

% ---- Define one glob pattern PER SCAN TYPE ----
% Adjust these to your actual BIDS naming. Check one real filename
% first, e.g. sub-MGHL201_ses-001_task-emotion_run-1_bold.nii.gz
% Order in this list = session order CONN will assign (see below).
scan_defs = struct( ...
    'label',   {'task_emotion_run1', 'task_emotion_run2', 'rest_run1'}, ...
    'pattern', { ...
        fullfile(BIDS_ROOT, 'sub-MGHL2*', 'ses-001', 'func', '*task-emotion_run-01_bold.nii.gz'), ...
        fullfile(BIDS_ROOT, 'sub-MGHL2*', 'ses-001', 'func', '*task-emotion_run-02_bold.nii.gz'), ...
        fullfile(BIDS_ROOT, 'sub-MGHL2*', 'ses-001', 'func', '*task-rest_bold.nii.gz') ...
    }, ...
    'type',    {'task','task','rest'} ...   % used only if USE_MANUAL_TR = true
    );

% Structural file pattern — set to '' to skip structural import
STRUCT_PATTERN = fullfile(BIDS_ROOT, 'sub-MGHL2*', 'ses-001', 'anat', '*ses-001_T1w.nii.gz');

%% ------------------- FIND FILES FOR EACH SCAN TYPE -------------------

nscantypes = numel(scan_defs);
all_subjects = {};

for k = 1:nscantypes
    files = cellstr(conn_dir(scan_defs(k).pattern));
    files = files(~cellfun(@isempty, files));
    tokens = regexp(files, 'sub-([A-Za-z0-9]+)', 'tokens', 'once');
    if any(cellfun(@isempty, tokens))
        error('Could not parse subject ID from a matched file for scan type "%s". Check pattern:\n  %s', scan_defs(k).label, scan_defs(k).pattern);
    end
    subj_ids = cellfun(@(x) x{1}, tokens, 'UniformOutput', false);

    [u, ~, ic] = unique(subj_ids);
    counts = accumarray(ic, 1);
    if any(counts > 1)
        bad = u(counts > 1);
        fprintf('\nScan type "%s" matched more than one file for the following subject(s):\n', scan_defs(k).label);
        for bi = 1:numel(bad)
            fprintf('  %s:\n', bad{bi});
            dupfiles = files(strcmp(subj_ids, bad{bi}));
            for fi = 1:numel(dupfiles)
                fprintf('    %s\n', dupfiles{fi});
            end
        end
        error('Scan type "%s" matched more than one file for subject(s): %s. Tighten the pattern (see file list printed above).', scan_defs(k).label, strjoin(bad, ', '));
    end

    scan_defs(k).files    = files;
    scan_defs(k).subj_ids = subj_ids;

    fprintf('Scan type "%-18s": %d file(s) found\n', scan_defs(k).label, numel(files));
    all_subjects = union(all_subjects, subj_ids);
end

all_subjects = sort(all_subjects);
nsubjects = numel(all_subjects);
fprintf('\nTotal unique subjects across all scan types: %d\n', nsubjects);

%% ------------------- FIND STRUCTURAL FILES (optional) -------------------

do_structural = ~isempty(STRUCT_PATTERN);
if do_structural
    struct_files = cellstr(conn_dir(STRUCT_PATTERN));
    struct_files = struct_files(~cellfun(@isempty, struct_files));
    struct_tokens = regexp(struct_files, 'sub-([A-Za-z0-9]+)', 'tokens', 'once');
    struct_subj_ids = cellfun(@(x) x{1}, struct_tokens, 'UniformOutput', false);

    [u, ~, ic] = unique(struct_subj_ids);
    counts = accumarray(ic, 1);
    if any(counts > 1)
        bad = u(counts > 1);
        error('STRUCT_PATTERN matched more than one file for subject(s): %s. Tighten the pattern.', strjoin(bad, ', '));
    end
end

%% ------------------- BUILD PER-SUBJECT SESSION LISTS -------------------
% For each subject, include whichever scan types they actually have,
% IN THE ORDER DEFINED IN scan_defs (so session order is consistent
% and documented across subjects, even when some sessions are missing).

session_map = cell(nsubjects, 1);   % session_map{nsub} = cell array of scan_defs labels, in session order
for nsub = 1:nsubjects
    subj = all_subjects{nsub};
    labels_here = {};
    files_here  = {};
    for k = 1:nscantypes
        idx = find(strcmp(scan_defs(k).subj_ids, subj), 1);
        if ~isempty(idx)
            labels_here{end+1} = scan_defs(k).label;          %#ok<AGROW>
            files_here{end+1}  = scan_defs(k).files{idx};      %#ok<AGROW>
        end
    end
    if isempty(files_here)
        warning('Subject %s matched no scan types — skipping.', subj);
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
        subj = all_subjects{nsub};
        sidx = find(strcmp(struct_subj_ids, subj), 1);
        if ~isempty(sidx)
            batch.Setup.structurals{nsub} = struct_files{sidx};
        else
            warning('No structural file found for subject %s — leaving structural unset.', subj);
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
