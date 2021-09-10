function SI = parse_SI_metadata(info)
% SI = parse_SI_metadata(info)
% Returns the ScanImage 'Software' metadata from the first frame that it 
% can find it for.


%% Main

% Check validity of the info 
if isfield(info,'Software')
    if ~strcmp(info(1).Software(1:2),'SI') % check for scan image marker
        SI = [];
        warning('Metadata did not contain ScanImage metadata. Metadata only exists in the raw ScanImage output.')
        return
    end
else
    SI = [];
    warning('Metadata did not contain ScanImage metadata. Metadata only exists in the raw ScanImage output.')
    return
end

% Extract information into structure
SI = struct;
meta = strsplit(info(1).Software,'\n');
for xline = 1:numel(meta)
    data = meta{xline};
    if isempty(data)
        continue
    end
    data = strsplit(data,' = '); % now split in two, with identifier and value
    
    SI(xline).Software = data{1};
    
    % Convert the string into its matlab variable (by writing the string as
    % a script)
    SI(xline).Value = eval(data{2});
end
%%
ImageDescription = struct;
for xfile = 1:numel(info)
    desc = info(xfile).ImageDescription;
    desc = strsplit(desc,'\n');
    for x = 1:numel(desc)
        if contains(desc{x},' = ')
            data = strsplit(desc{x},' = ');
            ImageDescription(xfile).(data{1}) = eval(data{2});
        end
    end
end
