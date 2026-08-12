%% CONN batch: task conditions only (Run 1 + Run 2)
% -------------------------------------------------------------------
% Adds condition (onset/duration) definitions to an EXISTING CONN
% project — run this AFTER conn_setup.m has finished and you've
% confirmed the resulting .mat looks right.
%
% Conditions are only defined for sessions 1 and 2 (task_emotion_run1,
% task_emotion_run2, per the session order conn_setup.m assigns via
% scan_defs). Session 3 (rest_run1) is intentionally left with no
% conditions defined — it's a resting scan with no task blocks.
%
% NOTE: 'taskrest' below is a CONDITION NAME — short fixation/rest
% blocks embedded within each task run — deliberately NOT named 'rest',
% because CONN automatically assigns an implicit whole-scan 'rest'
% condition to any session (like rest_run1, session 3) that has no
% explicit conditions defined. Naming this condition 'rest' too would
% collide with that, pooling the short in-task fixation blocks together
% with the entire independent resting-state scan under one label.
%
% Setup.isnew = 0 --> add to the existing project, don't create a new one.
% Setup.done  = 1 --> actually run/finalize this Setup step (required
%                     for CONN to validate and register the new
%                     conditions against the existing data).
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

condnames = {'shiver','neutral','joy','fear','taskrest'};
batch.Setup.conditions.names = condnames;

% CONN expects one onsets/durations entry per session for every
% condition/subject, even for sessions where the condition doesn't
% apply — an empty array means "zero occurrences here", not "undefined".
% Read the real session count from the project rather than hardcoding
% it, so this still works if conn_setup.m's scan_defs ever changes.
NSESSIONS = max(proj.CONN_x.Setup.nsessions);

for nsub = 1:NSUBJECTS
    for ncond = 1:numel(condnames)
        cname = condnames{ncond};

        for nses = 1:NSESSIONS
            batch.Setup.conditions.onsets{ncond}{nsub}{nses}    = [];
            batch.Setup.conditions.durations{ncond}{nsub}{nses} = [];
        end

        % Session 1 = Run 1
        batch.Setup.conditions.onsets{ncond}{nsub}{1}    = run1.(cname).onsets;
        batch.Setup.conditions.durations{ncond}{nsub}{1} = run1.(cname).durations;

        % Session 2 = Run 2
        batch.Setup.conditions.onsets{ncond}{nsub}{2}    = run2.(cname).onsets;
        batch.Setup.conditions.durations{ncond}{nsub}{2} = run2.(cname).durations;
    end
end

batch.Setup.done      = 1;
batch.Setup.overwrite = 1;

%% ------------------- RUN -------------------

conn_batch(batch);

fprintf('\nDone. Task conditions (%s) added for %d subject(s) in:\n  %s\n', strjoin(condnames, ', '), NSUBJECTS, batch.filename);
