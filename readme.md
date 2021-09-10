Processing of ScanImage exported data, for axon/dendrite imaging.

# Quickstart

- The folder must be on the Path
- Motion correction
  - Use `correct_motion_default` in the Command Window to run motion correction
    - Select template file
    - Select folder of raw data
    - Select folder to save motion corrected data into
  - Outputs
    - Motion corrected data
    - mclog.mat : motion correction pixel shifts
    - totalaverage.tif : average of every frame motion corrected
    - trial_averages.mat : matrix of each file's average
- Fluorescence extraction
  - Use `readroi` in the Command Window to run
    - Select RoiSet.zip file
    - Select folder with files to read
  - Outputs
    - Facrosstrials.mat : {nTrials,nRois} cell array with traces of each
    - roidata_meta.mat : struct of metadata used to generate Facrosstrials.mat

# Motion correction

- Rigid motion correction works for zoomed in FOVs because even minute brain movement looks gross at the dendrite/spine level.
- Whole files are loaded in to RAM, so hopefully your .tifs aren't too large
- `MotionCorrector` and `ROIReader` are [objects](https://au.mathworks.com/company/newsletters/articles/introduction-to-object-oriented-programming-in-matlab.html), and their internals are exposed which allows building out of function
- `visualise_rois` and `mclogplot` make plots of data
  - `mclogplot` interpretation: the *change* in colour indicates a change in x-y location. The colour itself is not particularly informative.

### Specialised usage

#### Motion correcting multiple sessions

Rather than using the UI (which is `MotionCorrector.getdirs_ui()`) to get the locations of the files, you would need to write your own thing to generate a list of directories and paths to iterate over. You might use a spreadsheet to instruct which sessions to apply motion correction to.

```matlab
mc = MotionCorrector; % initialise the object
for session = 1:numel(rawdirs)

    % pull out an individual session's paths
    rawdir = rawdirs{session};
    savedir = savedirs{session};
    templatepath = templatepaths{session};

    mc.motion_correct_folder(rawdir,templatepath,savedir); % apply motion correction onto a session
end
```

In this example, you might use a .csv to write down each session that you want motion correct and apply the process to, and then the `for` loop would extract the values.

#### Changing motion correction parameters

Parameters that you may normally not change can be modified before commencing  the motion correction.

```matlab
mc = MotionCorrector;
mc.correctionlimit = 30; % set the maximum number of pixels that are allowed to be moved

```

## Fine details

### Phase-correlation

The motion correction uses a [phase correlation](https://en.wikipedia.org/wiki/Phase_correlation) to determine the pixel offsets required. Originally the script used Naoya Takahashi's implementation, but it now uses ScanImage's which is faster.

### Loading

ScanImage provides a function specifically written to read their output data and the speed increase is substantial.

The `readsitiff()` function is a wrapper function for this, and it should be used because the ScanImage function reads the data transposed (mirrored about the diagonal compared to what any other reader would extract).

### Saving

`saveastiff()` is used for two reasons:

- The motion corrected data is saved in `int16` format instead of `uint16`, meaning that the values are the same as raw data (Which isn't true if `imwrite()` is used because it can't save `int16` format)
- The data is saved in volume, not with a loop, so it's faster

# Extracting fluorescence

Some alignment changes have been made to make an ROI's pixel mask align with what was drawn in Fiji. 

1. Each pixel is defined according to an integer coordinate.
2. Therefore, because each ROI is drawn using points on the vertices of each pixel, all Fiji ROI shapes should be expressed with 0.5 rather than as integers.

This is just a small detail that arises because Fiji treats the top left point of the image as `[0,0]`, so this difference in how MATLAB treats pixels and Fiji defines ROIs can cause very small and unexpected differences in defining which pixel is a part of an ROI or not.