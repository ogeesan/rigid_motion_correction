function correct_motion_example(varargin)
% correct_motion
% A wrapper script

p = inputParser;
p.addParameter('saveresult',true);
p.parse(varargin{:});

mc = MotionCorrector;
mc.save_result = p.Results.saveresult; % determine if motion corrected .tif files are output

dirs = mc.getdirs_ui(); % user input to determine what to do
mc.motion_correct_folder(dirs.rawdir,dirs.templatepath,dirs.savedir); % run the motion correction
end
