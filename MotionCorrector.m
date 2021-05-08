classdef MotionCorrector
% Motion correction class
% Contains low-level functions that a motion correction script might want to use
    
%{
    Example usage:
    mc = MotionCorrector;
    mc.run
%}
properties
    templateimg % template image
    correctionlimit = 15 % the maximum number for frame offset
    kernel = [];
    reader % scanimage reader object

    save_result = true; % if true, save motion corrected tifs. Otherwise it only outputs mclog

end

methods
    function obj = MotionCorrector
        % Check that major time-saving functions are on the path
        assert(exist('saveastiff.m','file') == 2,'Volume saving function not recognised.')
        assert(exist('+ScanImageTiffReader','dir'),'Volume loading not found.')
    end

    function run(obj)
        % Top-level run function which is equivalent to the old correct_motion_GS

        dirs = obj.getdirs_ui(); % user input to determine what to do
        obj.motion_correct_folder(dirs.rawdir,dirs.templatepath,dirs.savedir); % run the motion correction
    end


    function mclog = motion_correct_folder(obj,rawdir,templatepath,savedir)
        % The core function
        baseinfo = imfinfo(templatepath);
        nFrames = numel(baseinfo);
        if nFrames == 1
            base = imread(templatepath,'Info',baseinfo);
            obj.templateimg = base;
        else
            error('Template image is multiple files, should be a single frame.')
        end
        
        imheight = baseinfo.Height; % don't assume the size of each frame
        imwidth = baseinfo.Width;
        
        tiffopts.overwrite = true; % make saveastiff overwrite if there's a file
        tiffopts.message = false; % prevent saveastiff from reporting each save

        filelist = dir(fullfile(rawdir,'/*.tif')); % raw data from SI will be tif and not tiff
        nFiles = numel(filelist);
        
        % Initialise storage and reporters
        mclog = struct;
        loop_times = NaN(1,nFiles);
        trial_avgs = NaN(imheight,imwidth,nFiles);
        fprintf('%s Commencing motion correction of %i files\n\tRaw: %s\n\tOut: %s\n',...
                datestr(now,13),nFiles,rawdir,savedir)
        fprintf('Total:     ');
        fprintf([repmat('.',1,nFiles) '\n'])
        fprintf('Progress:  \n')
        loopstart = tic;
        
        % Initialise the parallel toolbox silently
        try
            evalc('parpool()'); % suppress the parpool message
        catch % if parallel toolbox isn't installed then it fails silently
        end
        
        parfor xfile = 1:nFiles % uses the Parallel Computing Toolbox 
            tic
            rawpath = fullfile(filelist(xfile).folder,filelist(xfile).name);
            vol = readsitiff(rawpath); % use ScanImage's fast tif reader
            shifts = obj.find_video_offsets(vol); % calculate frame offsets of the video

            % Record mclog output
            mclog(xfile).name = rawpath;
            mclog(xfile).vshift = shifts(:, 1);
            mclog(xfile).hshift = shifts(:, 2);
            
            % Apply the calculated pixel offsets onto the data
            vol = obj.apply_shifts(vol,shifts);
            trial_avgs(:,:,xfile) = mean(vol,3); % record the average of a trial
            
            if obj.save_result
                [~, fpath] = fileparts(rawpath);
                fpath = fullfile(savedir,[fpath '_mc.tif']);
                saveastiff(vol,fpath,tiffopts); % save the entire volume at once
            end
            
            % Report what happened
            loop_times(xfile) = toc;
            fprintf('\b|\n');
        end
        fprintf('%s Motion correction completed in %.1f seconds\n',...
                 datestr(now,13),toc(loopstart));
        
        basepath = fileparts(templatepath);
        save(fullfile(basepath,'mclog.mat'),'mclog');
        save(fullfile(basepath,'trial_avgs.mat'),'trial_avgs')
        saveastiff(mean(trial_avgs,3),fullfile(basepath,'totalaverage.tif'),tiffopts);

        trial_avgs = mean(trial_avgs,3) .* 1000;
        obj.outcome_plot(mclog,loop_times,trial_avgs,rawdir)

    end

    function outcome_plot(~,mclog,loop_times,trial_avgs,rawdir)
        % Create a figure to report that the session was completed
        figure('Name','Operation completed');
        
        % Show what the motion correction
        subplot(5,8,[1:4 9:12 17:20 25:28])
        imagesc(trial_avgs,[min(trial_avgs,[],'all') prctile(trial_avgs(:),95)]) % plot what the totalaverage.tif looks like
        xticklabels([]);yticklabels([]);title('totalaverage.tif')
        axis square
        colormap('gray')
        colorbar
        
        % Show motion correction x-y
        subplot(5,8,[5:8 13:16 21:24 29:32])
        mclogplot(mclog);
        set(gca,'TickDir','out')
        xlabel('Frame');ylabel('File')
        title('Motion correction visualisation')
        
        % Time to finish each loop
        subplot(5,8,33:40)
        bar(loop_times,'EdgeAlpha',0,'BarWidth',1) % plot time taken for each loop
        xlabel('Loop');ylabel('Time (s)');title('Time per loop');yline(mean(loop_times),':');
        
        sgtitle(rawdir,'Interpreter','none')
    end


    %% Low level functions
    function shift = corpeak2(obj,frame,base)
        % The actual act of motion correction.
        % A phase-correlation is used to find the x-y shift that would result in the highest
        % correlation between the frame and the base image.
        % base is an optional argument, where otherwise it takes obj.templateimg

        if nargin < 3; base = obj.templateimg; end

        [height, width] = size(base);
        base = base(:, 33 : width - 32); % Edge of the movie is not involved in the following calculation
        frame = frame(:, 33 : width - 32); % Edge of the movie is not involved in the following calculation
        width = width - 64;

        % fast Fourier transforms
        fourier_base = fft2(double(base));
        fourier_frame = fft2(double(frame));

        % kernel is used to define a filter? I don't know
        if ~isempty(obj.kernel)
            fourier_frame = fourier_frame .* obj.kernel;
            buf = ifft2(fourier_frame);
            buf = ifftshift(buf);
            fourier_frame = fft2(buf);
        end

        buf = fourier_base .* conj(fourier_frame); % complex double
        cf = ifft2(buf); % inverse fast Fourier transform - the phase correlation, imagesc(cf) if you want to see it

        % restrict search window of max correlation search
        % correctionlimit = opts.corrlimit; % maximum value in one direction
        cf(obj.correctionlimit + 1 : height - obj.correctionlimit, :) = NaN;
        cf(:, obj.correctionlimit + 1 : width - obj.correctionlimit) = NaN;
        % cf(16 : height - 15, :) = 0; % original
        % cf(:, 16 : width - 15) = 0;

        % get xy coords of max value in cf (which corresponds to the offset)
        [mcf1, vertidxs] = max(cf, [], 1); % the maximum values in each column - a vector of maxes from each column
        [~, horzidx] = max(mcf1); % the maximum values in the row of maximums - index of the max i.e. horizontal index

        % account for the size of the image and direction and stuff
        if vertidxs(horzidx) > height / 2 % if
            vertical = vertidxs(horzidx) - height - 1;
        else
            vertical = vertidxs(horzidx) - 1;
        end
        if horzidx > width / 2
            horizontal = horzidx - width - 1;
        else
            horizontal = horzidx - 1;
        end
        shift = [vertical horizontal]; % row-column for the amount of shift
    end


    function shifts = find_video_offsets(obj,vol,base)
        % Applies motion correction on each frame of a volume
        if nargin < 3
            base = obj.templateimg;
        end
        nFrames = size(vol,3); % assumes 3rd dimensions is the z-axis
        shifts = NaN(nFrames,2);
        for xframe = 1:nFrames
            shifts(xframe,:) = obj.corpeak2(vol(:,:,xframe));
        end
    end


    function dirs = getdirs_ui(~)
        % Interface to select files
        [fname, basedir] = uigetfile('*.tif*', 'Pick a Tif-file for base image');
        if isequal(fname, 0) || isequal(basedir, 0)
            disp('User canceled')
            return;
        end
        current_directory = pwd; % save where you currently are for later
        cd(basedir); % cd() sets the current directory (to easily specify the next two path names)
        impath = fullfile(basedir, fname); % the location of the base image

        % raw files
        rawdir = uigetdir('*.tif*', 'Select folder containing Tif-files to motion correct'); % location of raw files
        if isequal(rawdir, 0)
            disp('User canceled')
            return;
        end

        % new save location for motion corrected files
        savedir = uigetdir([], 'Select a folder to save motion corrected files into');
        if isequal(savedir, 0)
            disp('User canceled')
            return;
        end

        assert(~strcmp(basedir,rawdir),'Base file and raw files should not be in the same place.') % it's just bad practice yo, keep the raw data in its own folder

        % Places
        dirs.fname = fname;
        dirs.basedir = basedir;
        dirs.templatepath = fullfile(basedir,fname);
        dirs.rawdir = rawdir;
        dirs.savedir = savedir;
        cd(current_directory)
    end


    function vol = apply_shifts(obj,vol,shifts)
        nFrames = size(shifts,1);
        for xframe = 1:nFrames
            vol(:,:,xframe) = circshift(vol(:,:,xframe),shifts(xframe,:));
        end
    end
end
end