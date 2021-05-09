function [RGB, HSV] = visualise_rois(roimasks,baseimg,varargin)
% [RGB, HSV] = visualise_rois(roimasks,baseimg,___)
% Inputs
% ------
%   roimasks : cell array
%       Each cell contains index of pixels for the ROI
%   baseimg: 2D matrix or []
%       Image to project rois onto
% Optional name-pair arguments
%   roilist : vector 
%       defines which rois in roimasks to show, defaults to all roimasks
%   hues : vector (0-1)
%       Values for each roi (in roimasks) to hue, defaults to random
%   imsize : int
%       size of frame to project RGBvis onto
%   
% George Stuyt May 2021

%% Parse parameters
nRois = numel(roimasks);

p = inputParser;
p.addOptional('roilist',1:nRois);
p.addParameter('hues','default');
p.addParameter('imsize',512);
p.addParameter('dims',[]);
p.addParameter('usesat',false);
p.parse(varargin{:});

roilist = p.Results.roilist;

% Determine size of frame to project rois onto
if ~isempty(baseimg)
    dims = NaN(1,2);
    [dims(1), dims(2)] = size(baseimg);
elseif isempty(p.Results.dims)
    dims = [p.Results.imsize p.Results.imsize];
else
    dims = p.Results.dims;
end
assert(~isempty(dims),'Something went wrong, notify George')

% Decide hues
if strcmp(p.Results.hues,'default')
    rng('default')
    huelist = rand(1,nRois);
else
    huelist = p.Results.hues;
end

%% Build RGB visualisation
%         Hue: colour of each ROI
%  Saturation: how coloured each pixel is
%       Value: brightness of each pixel
H = zeros(dims(1),dims(2));
S = H;

% Determine brightness of each pixel
if isempty(baseimg) % if no base image
    V = H; % brightness is set to 1 for each ROI pixel
else % if there is a base image
    % Make the brightness of each pixel what's in the base image
    % Rescale to 0-1 if necessary
    [minval, maxval] = bounds(baseimg,'all');
    if minval < 0 || maxval > 1
        V = rescale(baseimg,'InputMax',prctile(baseimg,99,'all'));
    else
        V = baseimg;
    end
end

% Set hue and saturation for each pixel vale
for xroi = 1:numel(roilist)
    roi = roilist(xroi);
    hue = huelist(roi);
    
    H(roimasks{roi}) = hue;
    if p.Results.usesat
        S(roimasks{roi}) = 1; % make colour the maximum possible
    else
        S(roimasks{roi}) = V(roimasks{roi}); % make colour match the intensity of the image
    end
end

HSV = cat(3,H,S,V);
RGB = hsv2rgb(HSV);