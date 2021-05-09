classdef ROIReader
properties    
    use_raw = false;
    minvalue = 100; % raw data values below this amount will be set to zero, as it's dark noise
    preventoverlap = true;
end


methods
    %% Higher level functions
    function run(obj,roisetpath,readdir)
        
        % Create paths
        basedir = fileparts(roisetpath);
        fpaths = obj.acquire_fpaths(readdir);
        
        % Create ROI masks
        info = imfinfo(fpaths{1});
        imheight = info(1).Height;
        imwidth = info(1).Width;
        FijiRois = ReadImageJROI(roisetpath);
        roimasks = obj.fijirois2masks(...
            FijiRois,...
            imheight,imwidth);
        
        % Calculate roimeans
        if obj.use_raw
            mclog = load(fullfile(basedir,'mclog.mat'),'mclog'); 
            assert(~isempty(fields(mclog)),'mclog is empty')
            roimeans = obj.calculate_roimeans_from_raw(fpaths,roimasks,mclog);
        else
            roimeans = obj.calculate_roimeans(fpaths,roimasks);
        end
        
        fpath = fullfile(basedir,'totalaverage.tif');
        if isfile(fpath)
            baseimg = imread(fpath);
        else
            baseimg = [];
        end
        obj.plot(roimeans,roimasks,baseimg)
        
        % --  Package information and save it
        save(fullfile(basedir,'Facrosstrials.mat'),'roimeans');
        
        % Save the metadata about how the traces were extracted
        roidata = struct;
        roidata.roimasks = roimasks;
        roidata.FijiRois = FijiRois;
        roidata.imheight = imheight;
        roidata.imwidth = imwidth;
        roidata.minvalue = obj.minvalue;
        roidata.preventoverlap = obj.preventoverlap;
        roidata.use_raw = obj.use_raw;
        save(fullfile(basedir,'FAT_metadata.mat'),'roidata');
        
    end
    
    
    function roimeans = calculate_roimeans(obj,filepaths,roimasks)
        nRois = numel(roimasks);
        nFiles = numel(filepaths);
        roimeans = cell(nFiles,nRois);
        for xfile = 1:nFiles
            vol = readsitiff(filepaths{xfile});
            roimeans(xfile,:) = obj.read_single_volume(vol,roimasks);
        end
    end
    
    
    function roimeans = calculate_roimeans_from_raw(obj,fpaths,roimasks,mclog)
        
        mc = MotionCorrector;
        nFiles = numel(fpaths);
        nRois = numel(roimasks);
        roimeans = cell(nFiles,nRois);
        for xfile = 1:nFiles
            fpath = fpaths{xfile};
            vol = readsitiff(fpath);
            vol = mc.apply_shifts(vol,[mclog(xfile).vshift mclog(xfile).hshift]);
            roimeans(xfile,:) = obj.read_single_volume(vol,roimasks);
        end
    end
    
    
    %% Lower level functions
    function [roisetpath, readdir] = acquire_dirs_ui(~)
        % User-interface to select files
        [fname, basedir] = uigetfile('*.*','Select RoiSet.zip file');
        current_directory = pwd;
        cd(basedir);
        readdir = uigetdir([], 'Select folder containing .tif files to read.'); % get folder where files to read are
        cd(current_directory) % return to original location
        
        roisetpath = fullfile(basedir,fname);
        if isequal(fname, 0) || isequal(basedir, 0) || isequal(readdir,0)
            error('User canceled.')
        end
    end
    
    
    function fpaths = acquire_fpaths(~,readdir)
        % Get list of files to read from a folder
        filestruct = dir(fullfile(readdir,'/*.tif*'));
        fpaths = cell(numel(filestruct),1);
        for x = 1:numel(filestruct)
            fpaths{x} = fullfile(filestruct(x).folder,filestruct(x).name);
        end
    end
    
    
    function roimasks = fijirois2masks(obj,FijiRois,imheight,imwidth)
        % Converts Fiji's ROI coordinates into indicies of each ROI
        % Inputs:
        %   FijiRois : the output of ReadImageJROIs()
        %   imheight and imwidth : size of the individual frame
        % Outputs:
        %   roimasks : 1,nRois cell of each ROIs pixel coordinates as an
        %              index
        [X,Y] = meshgrid(1:imwidth,1:imheight); % create grids with arbitrary numbers
        nRois = numel(FijiRois);
        roimasks = cell(1,nRois);
        for roi = 1:nRois
            roicoords = FijiRois{roi}.mnCoordinates + 0.5; % retrieve roi coordinates and add 0.5 to align with what was drawn in ImageJ
            [in, on] = inpolygon(X,Y,roicoords(:,1),roicoords(:,2)); % check which pixels are (entirely) in or on (the edge of) area defined by roicoords
            roimasks{roi} = find(in & ~on);
            %             roimasks(:,:,xroi) = in & ~on; % would be used if roimasks was a logical index
            %             roimasks(:,:,xroi) = inpolygon(X,Y,rois{xroi}.mnCoordinates(:,1),rois{xroi}.mnCoordinates(:,2)); % the old code
        end
        
        if obj.preventoverlap
            all_values = vertcat(roimasks{:});
            [~, w] = unique(all_values, 'stable' );
            duplicate_values = all_values(setdiff(1:numel(all_values), w ));
            for roi = 1:nRois
                roimasks{roi} = setdiff(roimasks{roi}, duplicate_values);
            end
        end
    end
    
    
    function plot(~,roimeans,roimasks,baseimg)
        
        figure('Name','Extraction complete')
        [nFiles, ~] = size(roimeans);
        nFrames_max = max(cellfun(@numel,roimeans),[],'all');
        subplot(1,2,1)
        for xfile = 1:nFiles
            plot(vertcat(roimeans{xfile,:})')
            
            hold on
        end
        hold off
        box off; grid on
        xlabel('Frame')
        ylabel('Raw F')
        xlim([0 nFrames_max])
        title('Raw traces')
        
        subplot(1,2,2)
        image(visualise_rois(roimasks,baseimg))
        axis square
        title('What it was read from')
    end
    
    
    function roimeans_volume = read_single_volume(obj,vol,roimasks)
        % Calculate the traces of a single video matrix
        nRois = numel(roimasks);
        vol = obj.volume2matrix(vol);
        vol(vol<obj.minvalue) = 0; % remove dark noise
        roimeans_volume = cell(1,nRois);
        for roi = 1:nRois
            roimeans_volume{roi} = mean(vol(roimasks{roi},:));
        end
    end
    
    
    function reshaped_vol = volume2matrix(~,vol)
        % Reshapes 3D video into 2D array
        [imheight, imwidth, nFrames] = size(vol);
        reshaped_vol = reshape(vol, [imwidth*imheight nFrames]);
    end
    
    
    function reshaped_vol = volume2matrix_check(~,vol)
        % reshapes the volume and checks that the values line up
        reshaped_vol = RoiReader.volume2matrix(vol);
        
        p = primes(imheight*imwidth);
        p = randsample(p,10);
        for x = 1:numel(p)
            idx = p(x);
            [row, col] = ind2sub([imheight imwidth],idx);
            assert(all(reshaped_vol(idx,:) == reshape(vol(row,col,:),[1 nFrames])),'Indexing is borked, notify George.')
        end
    end
end
end