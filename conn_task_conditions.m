%% CONN batch: task conditions only (Run 1 + Run 2)
% -------------------------------------------------------------------
% Adds condition (onset/duration) definitions to an EXISTING CONN
% project — run this AFTER conn_setup.m has finished and you've
% confirmed the resulting .mat looks right.
%
% Two DIFFERENT things are both called "rest" in this paradigm, and this
% script deliberately gives them different condition names:
%   - 'taskrest': the brief fixation/rest blocks embedded WITHIN each
%     task-emotion run (sessions 1 & 2, per run1/run2 tables below).
%   - 'rest': the separate, PURE resting-state scan (session 3,
%     rest_run1) — defined explicitly here as one block spanning the
%     entire session, rather than relying on CONN's implicit "whole
%     session is rest if no conditions are defined" behavior.
% 'taskrest' only applies to sessions 1 & 2; 'rest' only applies to
% session 3 — each is left undefined (empty) everywhere else.
%
% Setup.isnew = 0 --> add to the existing project, don't create a new one.
% Setup.done  = 0 --> ONLY store these condition definitions in the
%                     project; do NOT execute/finalize the Setup stage.
%                     Matches conn_setup.m's approach — Setup stays
%                     unfinalized so you can still add ROIs, covariates,
%                     etc. yourself before running Setup for real.
% -------------------------------------------------------------------
addpath('/autofs/space/nicc_003/users/holly/repo/spm12')
addpath('/autofs/space/nicc_003/users/holly/repo/conn_25b')

clear batch;

%% ------------------- USER SETTINGS (edit these) -------------------
% Must match the PROJECT_DIR / PROJECT_NAME used in conn_setup.m, so
% this points at the same project file.

PROJECT_DIR  = '/autofs/space/nicc_006/data/LETBI/BIDS/derivatives/conn_v25b';
PROJECT_NAME = 'MGHL2_emotion_rest';

batch.filename    = fullfile(PROJECT_DIR, [PROJECT_NAME '.mat']);
batch.Setup.isnew = 0;   % 0 = add to existing project

% Read subject count directly from the existing project rather than
% hardcoding it, so this can't silently drift out of sync with however
% many subjects conn_setup.m actually included (e.g. after exclusions).
proj = load(batch.filename, 'CONN_x');
NSUBJECTS = proj.CONN_x.Setup.nsubjects;
fprintf('Adding conditions for %d subject(s) in project:\n  %s\n', NSUBJECTS, batch.filename);

%% ---- Timing tables (seconds, from run start) ----

% RUN 1
run1.shiver.onsets     = [0];              run1.shiver.durations     = [21.5];
run1.neutral.onsets    = [21.5, 236.0];    run1.neutral.durations    = [30.25, 30.25];
run1.joy.onsets        = [51.75, 159.0, 266.25, 326.75];
run1.joy.durations     = [30.25, 30.25, 30.25, 30.25];
run1.fear.onsets       = [82.0, 128.75, 205.75, 296.5];
run1.fear.durations    = [30.25, 30.25, 30.25, 30.25];
run1.taskrest.onsets   = [112.25, 189.25]; run1.taskrest.durations   = [16.5, 16.5];

% RUN 2
run2.shiver.onsets     = [0];              run2.shiver.durations     = [21.5];
run2.joy.onsets        = [21.5, 82.0, 159.0, 219.5];
run2.joy.durations     = [30.25, 30.25, 30.25, 30.25];
run2.fear.onsets       = [51.75, 128.75, 249.75, 326.75];
run2.fear.durations    = [30.25, 30.25, 30.25, 30.25];
run2.neutral.onsets    = [189.25, 296.5];  run2.neutral.durations    = [30.25, 30.25];
run2.taskrest.onsets   = [112.25, 280.0];  run2.taskrest.durations   = [16.5, 16.5];

%% ---- Build conditions structure ----

% Session indices, matching the order conn_setup.m assigns via scan_defs.
RUN1_SESSION = 1;   % task_emotion_run1
RUN2_SESSION = 2;   % task_emotion_run2
REST_SESSION = 3;   % rest_run1 — the pure resting-state scan

task_condnames = {'shiver','neutral','joy','fear','taskrest'};
condnames = [task_condnames, {'rest'}];
batch.Setup.conditions.names = condnames;

% CONN expects one onsets/durations entry per session for every
% condition/subject, even for sessions where the condition doesn't
% apply — an empty array means "zero occurrences here", not "undefined".
% Read the real session count from the project rather than hardcoding
% it, so this still works if conn_setup.m's scan_defs ever changes.
NSESSIONS = max(proj.CONN_x.Setup.nsessions);

for nsub = 1:NSUBJECTS
    % Default every condition to "not present" in every session, then
    % fill in only where each condition actually applies.
    for ncond = 1:numel(condnames)
        for nses = 1:NSESSIONS
            batch.Setup.conditions.onsets{ncond}{nsub}{nses}    = [];
            batch.Setup.conditions.durations{ncond}{nsub}{nses} = [];
        end
    end

    % Task conditions (including 'taskrest') apply only within the
    % task-emotion runs, sessions 1 & 2.
    for ncond = 1:numel(task_condnames)
        cname = task_condnames{ncond};
        batch.Setup.conditions.onsets{ncond}{nsub}{RUN1_SESSION}    = run1.(cname).onsets;
        batch.Setup.conditions.durations{ncond}{nsub}{RUN1_SESSION} = run1.(cname).durations;
        batch.Setup.conditions.onsets{ncond}{nsub}{RUN2_SESSION}    = run2.(cname).onsets;
        batch.Setup.conditions.durations{ncond}{nsub}{RUN2_SESSION} = run2.(cname).durations;
    end

    % 'rest' applies only to session 3 — one block spanning the entire
    % resting-state scan (duration=inf means "to the end of the session").
    rest_idx = numel(condnames);
    batch.Setup.conditions.onsets{rest_idx}{nsub}{REST_SESSION}    = [0];
    batch.Setup.conditions.durations{rest_idx}{nsub}{REST_SESSION} = [inf];
end

batch.Setup.done      = 0;
batch.Setup.overwrite = 1;

%% ------------------- RUN -------------------

conn_batch(batch);

fprintf('\nDone. Task conditions (%s) stored for %d subject(s) in:\n  %s\n', strjoin(condnames, ', '), NSUBJECTS, batch.filename);
fprintf('Setup was NOT finalized (done=0) — continue setting up the project (ROIs, etc.) before running Setup for real.\n');
