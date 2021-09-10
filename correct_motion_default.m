function correct_motion_default(varargin)
% correct_motion
% A wrapper script

p = inputParser;
p.addParameter('saveresult',true); % if motion corrected .tif files are output
p.addParameter('parallel',true); % if parallel processing is used
p.parse(varargin{:});

%%
mc = MotionCorrector;
mc.save_result = p.Results.saveresult; 
mc.use_parallel_processing = p.Results.parallel;

dirs = mc.getdirs_ui(); % user input to determine what to do
%%
mc.motion_correct_files(dirs.fpaths,dirs.templatepath,dirs.savedir); % run the motion correction
end
