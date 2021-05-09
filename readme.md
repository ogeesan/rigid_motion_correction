
Pre-processing for ScanImage exported data.

# Quickstart
- The folder must be on the Path
- Motion correction
  - Use `correct_motion` in the Command Window to run motion correction
    - Select template file
    - Select folder of raw data
    - Select folder to save motion corrected data into
  - Outputs
    - Motion corrected data
    - mclog.mat : motion correction pixel shifts
    - totalaverage.tif : average of every frame motion corrected

# Usage
Question: in what situations does this work, and what situations does it not?
- Rigid motion correction works for zoomed in FOVs because even minute brain movement looks gross at the dendrite/spine level.
- The top-level methods like `MotionCorrector.run` are loading in the entire file, so if it is a file that is larger than RAM you could:
  - Use a different motion correction tool
  - Write your own script that uses the lower level functions in `MotionCorrector` to read in chunks of the file and then `MotionCorrector.find_video_offsets()` on those, after which you'd have to stitch things together.

Why the change? The functions used to motion correction have been exposed, which allows easier customisation of how things are done.

## Specialised usage
### Motion correcting multiple sessions
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

### Changing motion correction parameters
Parameters that you may normally not change can be modified before commencing  the motion correction.
```matlab
mc = MotionCorrector;
mc.correctionlimit = 30; % set the maximum number of pixels that are allowed to be moved
mc.motion_correct_folder()...
```


# Fine details
## Phase-correlation
The motion correction uses a [phase correlation](https://en.wikipedia.org/wiki/Phase_correlation) to determine the pixel offsets required.

## Loading
ScanImage provides a function specifically written to read their output data and the speed increase is substantial.

The `readsitiff()` function is a wrapper function for this, and it should be used because the ScanImage function reads the data transposed (mirrored about the diagonal compared to what any other reader would extract).

## Saving
`saveastiff()` is used for two reasons:
- The motion corrected data is saved in `int16` format instead of `uint16`, meaning that the values are the same as raw data (Which isn't true if `imwrite()` is used)
- The data is saved in volume, not with a loop, so it's faster
