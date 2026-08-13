%% CONN batch: task conditions only (Run 1 + Run 2), with per-subject
%% truncation for scans that aborted early
% -------------------------------------------------------------------
% Same paradigm/timing tables as before, BUT: some subjects' run-02
% scans aborted early (confirmed via spm_vol volume counts). Rather
% than assuming every session ran the full 357s, this script:
%   1. Reads each subject's ACTUAL number of volumes for run-01/run-02
%      directly from their functional files already registered in the
%      CONN project.
%   2. Computes actual scan duration = nvols * TR.
%   3. Drops any condition instance (onset+duration) that falls beyond
%      that subject's actual duration, rather than assuming full-length
%      theoretical timing for everyone.
%   4. Prints a report of exactly what got dropped, per subject, so you
%      have a record for your methods/QC notes.
%
% NOTE: a block straddling the cutoff (onset < actual_duration but
% onset+duration > actual_duration) is DROPPED ENTIRELY, not clipped —
% we don't have log evidence the stimulus/task continued playing after
% the scanner aborted, so partial modeling would be a guess. If you
% later obtain real presentation logs for the aborted subjects, use
% those instead — they're better ground truth than this reconstruction.
% -------------------------------------------------------------------
addpath('/autofs/space/nicc_003/users/holly/repo/spm12')
addpath('/autofs/space/nicc_003/users/holly/repo/conn_25b')

clear batch;

%% ------------------- USER SETTINGS -------------------

PROJECT_DIR  = '/autofs/space/nicc_006/data/LETBI/BIDS/derivatives/conn_v25b';
PROJECT_NAME = 'MGHL2_emotion_rest';

batch.filename    = fullfile(PROJECT_DIR, [PROJECT_NAME '.mat']);
batch.Setup.isnew = 0;

proj = load(batch.filename, 'CONN_x');
NSUBJECTS = proj.CONN_x.Setup.nsubjects;
TR        = proj.CONN_x.Setup.RT;
if numel(TR) > 1, TR = TR(1); end   % CONN_x.Setup.RT may be scalar or per-session; assumes constant TR here — verify if not

fprintf('Checking actual scan durations for %d subject(s), TR=%.3fs\n', NSUBJECTS, TR);

%% ------------------- Session indices -------------------

RUN1_SESSION = 1;
RUN2_SESSION = 2;
REST_SESSION = 3;

%% ------------------- Theoretical timing tables (seconds) -------------------

run1.shiver.onsets     = [0];              run1.shiver.durations     = [21.5];
run1.neutral.onsets    = [21.5, 236.0];    run1.neutral.durations    = [30.25, 30.25];
run1.joy.onsets        = [51.75, 159.0, 266.25, 326.75];
run1.joy.durations     = [30.25, 30.25, 30.25, 30.25];
run1.fear.onsets       = [82.0, 128.75, 205.75, 296.5];
run1.fear.durations    = [30.25, 30.25, 30.25, 30.25];
run1.taskrest.onsets   = [112.25, 189.25]; run1.taskrest.durations   = [16.5, 16.5];

run2.shiver.onsets     = [0];              run2.shiver.durations     = [21.5];
run2.joy.onsets        = [21.5, 82.0, 159.0, 219.5];
run2.joy.durations     = [30.25, 30.25, 30.25, 30.25];
run2.fear.onsets       = [51.75, 128.75, 249.75, 326.75];
run2.fear.durations    = [30.25, 30.25, 30.25, 30.25];
run2.neutral.onsets    = [189.25, 296.5];  run2.neutral.durations    = [30.25, 30.25];
run2.taskrest.onsets   = [112.25, 280.0];  run2.taskrest.durations   = [16.5, 16.5];

task_condnames = {'shiver','neutral','joy','fear','taskrest'};
condnames = [task_condnames, {'rest'}];
batch.Setup.conditions.names = condnames;

NSESSIONS = max(proj.CONN_x.Setup.nsessions);

%% ------------------- Helper: truncate onsets/durations to actual duration -------------------

function [ons_out, dur_out, ndropped] = truncate_condition(ons_in, dur_in, actual_duration)
    keep = (ons_in + dur_in) <= actual_duration;
    ons_out  = ons_in(keep);
    dur_out  = dur_in(keep);
    ndropped = sum(~keep);
end

%% ------------------- Main loop -------------------

for nsub = 1:NSUBJECTS

    % Initialize everything to empty first
    for ncond = 1:numel(condnames)
        for nses = 1:NSESSIONS
            batch.Setup.conditions.onsets{ncond}{nsub}{nses}    = [];
            batch.Setup.conditions.durations{ncond}{nsub}{nses} = [];
        end
    end

    % --- Get actual volume counts for run-01 and run-02 from the project's
    % --- already-registered functional files
    func1 = proj.CONN_x.Setup.functionals{nsub}{RUN1_SESSION}{1};
    func2 = proj.CONN_x.Setup.functionals{nsub}{RUN2_SESSION}{1};

    V1 = spm_vol(func1); nvols1 = numel(V1); actual_dur1 = nvols1 * TR;
    V2 = spm_vol(func2); nvols2 = numel(V2); actual_dur2 = nvols2 * TR;

    flagged1 = actual_dur1 < 357;   % theoretical full duration
    flagged2 = actual_dur2 < 357;

    if flagged1 || flagged2
        fprintf('\nSubject %d: ', nsub);
        if flagged1, fprintf('run-01 SHORT (%.1fs, %d vols) ', actual_dur1, nvols1); end
        if flagged2, fprintf('run-02 SHORT (%.1fs, %d vols) ', actual_dur2, nvols2); end
        fprintf('\n');
    end

    % --- Run 1 conditions, truncated to actual_dur1 ---
    for ncond = 1:numel(task_condnames)
        cname = task_condnames{ncond};
        [ons, dur, ndrop] = truncate_condition(run1.(cname).onsets, run1.(cname).durations, actual_dur1);
        batch.Setup.conditions.onsets{ncond}{nsub}{RUN1_SESSION}    = ons;
        batch.Setup.conditions.durations{ncond}{nsub}{RUN1_SESSION} = dur;
        if ndrop > 0
            fprintf('  DROPPED %d instance(s) of "%s" from run-01 (beyond %.1fs)\n', ndrop, cname, actual_dur1);
        end
    end

    % --- Run 2 conditions, truncated to actual_dur2 ---
    for ncond = 1:numel(task_condnames)
        cname = task_condnames{ncond};
        [ons, dur, ndrop] = truncate_condition(run2.(cname).onsets, run2.(cname).durations, actual_dur2);
        batch.Setup.conditions.onsets{ncond}{nsub}{RUN2_SESSION}    = ons;
        batch.Setup.conditions.durations{ncond}{nsub}{RUN2_SESSION} = dur;
        if ndrop > 0
            fprintf('  DROPPED %d instance(s) of "%s" from run-02 (beyond %.1fs)\n', ndrop, cname, actual_dur2);
        end
    end

    % --- Resting-state session: unaffected by this issue, spans full session ---
    rest_idx = numel(condnames);
    batch.Setup.conditions.onsets{rest_idx}{nsub}{REST_SESSION}    = [0];
    batch.Setup.conditions.durations{rest_idx}{nsub}{REST_SESSION} = [inf];
end

batch.Setup.done      = 0;
batch.Setup.overwrite = 1;

%% ------------------- RUN -------------------

conn_batch(batch);

fprintf('\nDone. Conditions stored for %d subject(s) in:\n  %s\n', NSUBJECTS, batch.filename);
fprintf('Review the DROPPED instance report above before proceeding —\n');
fprintf('any subject with dropped conditions has fewer trials for that\n');
fprintf('condition than others, which may need to be noted/handled at\n');
fprintf('the group level (e.g., minimum-trial-count exclusion criteria).\n');