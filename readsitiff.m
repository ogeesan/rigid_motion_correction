function vol = readsitiff(fpath)
% vol = readsitiff(fpath)
%   Wrapper script to read in ScanImage exported data, transposes the read-in
%   to match what would be loaded if any other reader was used.

    vol = ScanImageTiffReader.ScanImageTiffReader(fpath).data;
    % Reorder dimensions
    %   The reader has each frame transposed compared to what imread(), Fiji,
    %   and Napari read the data as, so each frame must be transposed before
    %   proceeding.
    vol = permute(vol,[2 1 3]); % still works even if the image is a single frame
end