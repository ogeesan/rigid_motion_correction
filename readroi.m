function readroi()
% readroi

RR = ROIReader; % Initialise object

% Define paths
[roisetpath,readdir] = RR.acquire_dirs_ui;
basedir = fileparts(roisetpath); % location to save Facrosstrials to
fpaths = RR.acquire_fpaths(readdir); % find all .tif files in the folder

tic
fprintf('%s Commenced reading of ROIs in: %s\n',datestr(now,13),readdir)

% Create ROI masks
info = imfinfo(fpaths{1});
imheight = info(1).Height;
imwidth = info(1).Width;
FijiRois = ReadImageJROI(roisetpath);
roimasks = RR.fijirois2masks(...
    FijiRois,...
    imheight,imwidth);

% Calculate roimeans
nRois = numel(roimasks);
nFiles = numel(fpaths);
roimeans = cell(nFiles,nRois);
fprintf(['Files: ' repmat('.',1,nFiles) '\n'])
fprintf( 'To go: \n');
for xfile = 1:nFiles
    roimeans(xfile,:) = RR.read_single_volume(...
        readsitiff(fpaths{xfile}),...
        roimasks);
    fprintf('\b|\n')
end

% Plot the output
fpath = fullfile(basedir,'totalaverage.tif'); % if the trial-average can be detected
if isfile(fpath)
    baseimg = imread(fpath);
else
    baseimg = [];
end
RR.plot(roimeans,roimasks,baseimg)
sgtitle(readdir,'Interpreter','none')

save(fullfile(basedir,'Facrosstrials.mat'),'roimeans');
fprintf('%s Completed reading in %.2f\n',datestr(now,13),toc)
end