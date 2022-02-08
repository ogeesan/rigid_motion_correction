classdef MotionCorrector
% Motion correction class
% Contains low-level functions that a motion correction script might want to use
% Core methods
%   mclog = motion_correct_folder(rawdir,templatepath,savedir)
    
properties
    templateimg % template image
    correctionlimit = 15 % the maximum number for frame offset
    kernel = [];
    corr_window_edge = 32 % the edge of the frame that will be excluded from motion correction
    height
    width
    
    calcmethod = 'scanimage' % other possibility is takahashi, which is slower
    
    use_parallel_processing = false;

    save_result = true; % if true, save motion corrected tifs. Otherwise it only outputs mclog
    

end

methods
    function obj = MotionCorrector
        % Check that major time-saving functions are on the path
        assert(exist('saveastiff.m','file') == 2,'Volume saving function not recognised.')
%         assert(exist('+ScanImageTiffReader','dir'),'Volume loading not found.')
    end


    function mclog = motion_correct_files(obj,fpaths,templatepath,savedir)
        % The core function
        baseinfo = imfinfo(templatepath);
        nFrames = numel(baseinfo);
        if nFrames == 1
            base = imread(templatepath,'Info',baseinfo);
            obj.templateimg = base;
        else
            error('Template image is multiple files, should be a single frame.')
        end
        
        imheight = baseinfo.Height; % don't assume the size of the frame
        imwidth = baseinfo.Width;
        
        tiffopts.overwrite = true; % make saveastiff overwrite if there's a file
        tiffopts.message = false; % prevent saveastiff from reporting each save
      
        nFiles = numel(fpaths);
        if nFiles == 0
            error('Failed to find any files')
        end
        if obj.check_memory(fpaths)
            warning('Files are big, behaviour of the script in this situation is unknown.')
        end
        
        % Initialise storage and reporters
        mclog = struct; % shifts for each file
        tif_metadatas = struct;
        mc_metadata = struct;
        loop_times = NaN(1,nFiles); % time taken to motion correct the file
        trial_avgs = NaN(imheight,imwidth,nFiles); % average of each file
        
        mc_metadata.template = templatepath;
        mc_metadata.correction_limit = obj.correctionlimit;
        mc_metadata.kernel = obj.kernel;
        mc_metadata.corr_window_edge = obj.corr_window_edge;
        
        fprintf('Total:     ');
        fprintf([repmat('.',1,nFiles) '\n'])
        fprintf('Progress:  \n')
        loopstart = tic;
        
        % Initialise the parallel toolbox silently
        if obj.use_parallel_processing
            try
                evalc('parpool()'); % suppress the parpool message
            catch % if parallel toolbox isn't installed then it fails silently
            end
        else
            try
            ps = parallel.Settings; % create Settings object
            og_pool_autocreate_Setting = ps.Pool.AutoCreate; % store the original state
            ps.Pool.AutoCreate = false; % prevent a parallel pool from being created
            catch
            end
        end
        
        parfor xfile = 1:nFiles % uses the Parallel Computing Toolbox (if installed)
            tic
            rawpath = fullfile(fpaths(xfile).folder,fpaths(xfile).name);
            vol = readsitiff(rawpath); % use ScanImage's fast tif reader
            shifts = obj.find_video_offsets(vol); % calculate frame offsets of the video
            
            % Record mclog output
            mclog(xfile).name = rawpath;
            mclog(xfile).vshift = shifts(:, 1);
            mclog(xfile).hshift = shifts(:, 2);
            info = imfinfo(rawpath);
            tif_metadatas(xfile).info = info(1);
            
            % Apply the calculated pixel offsets onto the data
            vol = obj.apply_shifts(vol,shifts);
            trial_avgs(:,:,xfile) = nanmean(vol,3); % record the average of a trial
            
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
        
        if ~obj.use_parallel_processing
            try
            ps.Pool.AutoCreate = og_pool_autocreate_Setting; % store the original state;
            catch
            end
        end
        
        % Save data into the same location as the template .tif
        basepath = fileparts(templatepath);
        save(fullfile(basepath,'mclog.mat'),'mclog','tif_metadatas','mc_metadata'); % save mclog and imfinfo() into the file
        save(fullfile(basepath,'trial_avgs.mat'),'trial_avgs')
        saveastiff(mean(trial_avgs,3),fullfile(basepath,'totalaverage.tif'),tiffopts);
        
        trial_avgs = mean(trial_avgs,3);
        obj.outcome_plot(mclog,loop_times,trial_avgs)
    end
    

    % Low level functions
    function vol = apply_shifts(~,vol,shifts)
        % Apply the already-calculated motion correction onto a video
        nFrames = size(shifts,1);
        for xframe = 1:nFrames
            vol(:,:,xframe) = circshift(vol(:,:,xframe),shifts(xframe,:));
        end
    end
    
    
    function flag = check_memory(~,directory)
        % Check whether file sizes are too large
        user = memory;
        system_mem = user.MemAvailableAllArrays;
        file_bytes = [directory.bytes];
        flag = false;
        if any(file_bytes*2 > system_mem)
            flag = true;
        end
    end
    
    
    function shift = corpeak2(obj,frame,fourier_base)
        % The actual act of motion correction.
        % A phase-correlation is used to find the x-y shift that would result in the highest
        % correlation between the frame and the base image.
        % base is an optional argument, where otherwise it takes obj.templateimg

        % Trim the data for motion correction
%         base = base(:, obj.corr_window_edge+1 : obj.width - obj.corr_window_edge);
        frame = frame(:, obj.corr_window_edge+1 : obj.width - obj.corr_window_edge);
        obj.width = obj.width - obj.corr_window_edge*2; % ! I don't know why this is only done for width

        % fast Fourier transforms
%         fourier_base = fft2(double(base));
        fourier_frame = fft2(double(frame));
        assert(all(size(fourier_base) == size(fourier_frame)),...
            "Size of images did not match.")

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
        cf(obj.correctionlimit + 1 : obj.height - obj.correctionlimit, :) = NaN;
        cf(:, obj.correctionlimit + 1 : obj.width - obj.correctionlimit) = NaN;
        % cf(16 : height - 15, :) = 0; % original
        % cf(:, 16 : width - 15) = 0;

        % get xy coords of max value in cf (which corresponds to the offset)
        [mcf1, vertidxs] = max(cf, [], 1); % the maximum values in each column - a vector of maxes from each column
        [~, horzidx] = max(mcf1); % the maximum values in the row of maximums - index of the max i.e. horizontal index

        % account for the size of the image and direction and stuff
        if vertidxs(horzidx) > obj.height / 2 % if
            vertical = vertidxs(horzidx) - obj.height - 1;
        else
            vertical = vertidxs(horzidx) - 1;
        end
        if horzidx > obj.width / 2
            horizontal = horzidx - obj.width - 1;
        else
            horizontal = horzidx - 1;
        end
        shift = [vertical horizontal]; % row-column for the amount of shift
    end
    
    
    function [shifts, quality, cii, cjj] = scanimagecorrect(~,frame,preprocessedbase)
        [~, shifts, quality, cii, cjj] = motionCorrection.fftCorrSideProj_detectMotionFcn(preprocessedbase,frame);
    end

    function preprocessed_base = scanimage_base_preprocess(obj,baseimg, preprocess_method)
        % Precalculates fourier transformation of the template image
        switch preprocess_method
            case 'scanimage'
                [~,preprocessed_base] = motionCorrection.fftCorrSideProj_preprocessFcn(baseimg);
            case 'takahashi'
                baseimg = baseimg(:, obj.corr_window_edge+1 : obj.width - obj.corr_window_edge);
                preprocessed_base = ff2t(double(baseimg));
        end
    end


    function shifts = find_video_offsets(obj,vol,base)
        % Applies motion correction on each frame of a volume
        if nargin < 3
            base = obj.templateimg;
        end
        nFrames = size(vol,3); % assumes 3rd dimensions is the z-axis
        shifts = NaN(nFrames,2);
        [obj.height, obj.width] = size(base);
        
        switch obj.calcmethod
            case 'scanimage'
                preprocessed_base = obj.scanimage_base_preprocess(base, obj.calcmethod);
                for xframe = 1:nFrames
                    shifts(xframe,:) = obj.scanimagecorrect(vol(:,:,xframe),preprocessed_base);
                end
            case 'takahashi'
                fourier_base = obj.scanimage_base_preprocess(base, obj.calcmethod);
                for xframe = 1:nFrames
                    shifts(xframe,:) = obj.corpeak2(vol(:,:,xframe),fourier_base);
                end
            otherwise
                error('Calculation method obj.calcmethod not recognised: %s', obj.calcmethod)
        end
    end


    function dirs = getdirs_ui(obj)
        % dirs = getdirs_ui
        % Interface to select files
        
        dirs = struct;
        
        [fname, basedir] = uigetfile('*.tif*', 'Pick a Tif-file for base image');
        if isequal(fname, 0) || isequal(basedir, 0)
            error('User canceled')
        end
        current_directory = pwd; % save where you currently are for later
        cd(basedir); % cd() sets the current directory (to easily specify the next two path names)
        dirs.fname = fname;
        dirs.basedir = basedir;
        dirs.templatepath = fullfile(basedir,fname);

        % raw files
        rawdir = uigetdir('*.tif*', 'Select folder containing Tif-files to motion correct'); % location of raw files
        if isequal(rawdir, 0)
            error('User canceled')
        end
        dirs.rawdir = rawdir;
        dirs.fpaths = dir(fullfile(rawdir,'/*.tif*'));
 
        assert(~strcmp(basedir,rawdir),'Base file and raw files should not be in the same place.') % it's just bad practice yo, keep the raw data in its own folder

        % new save location for motion corrected files
        if obj.save_result
            savedir = uigetdir([], 'Select a folder to save motion corrected files into');
            if isequal(savedir, 0)
                error('User canceled')
            end    
            dirs.savedir = savedir;
        else
            dirs.savedir = [];
        end

        
        cd(current_directory)
    end
    
    
    function outcome_plot(~,mclog,loop_times,trial_avgs)
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
    end
end
end