function correct_motion_si()
mc = MotionCorrector;
%% Determine list of files
dirs = mc.getdirs_ui;
filelist = dir(fullfile(dirs.rawdir,'/*.tif')); % raw data from SI will be tif and not tiff

%% Load template file
baseinfo = imfinfo(dirs.basepath);
nFrames = numel(baseinfo);
if nFrames == 1
    base = imread(dirs.basepath,'Info',baseinfo);
    mc.templateimg = base;
else
    error('Template image is multiple files, this might not be a good idea.')
end

%% Apply files
nFiles = numel(filelist);
fprintf('%s Motion correcting %i files\nfrom: %s\nto: %s\n',...
        datestr(now,13),dirs.rawdir,dirs.basedir)

mclog = struct;
% trial_avgs = cell(1,nFiles);
for xfile = 1:nFiles
    rawpath = fullfile(filelist(xfile).folder,filelist(xfile).name);
    vol = readsitiff(rawpath);
    shifts = mc.find_video_offsets(vol);
    mclog(xfile) = mc.construct_file_mclog(rawpath,shifts);
end
save(fullfile(dirs.basedir,'mclog.mat'),'mclog')
end