function correct_motion()
% correct_motion
% A wrapper script
mc = MotionCorrector;
dirs = mc.getdirs_ui(); % user input to determine what to do
mc.motion_correct_folder(dirs.rawdir,dirs.templatepath,dirs.savedir); % run the motion correction
end
