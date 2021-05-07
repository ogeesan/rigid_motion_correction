# Loading
ScanImage provides a function specifically written to read their output data. The speed increase is pretty substantial.

The `readsitiff()` function is a wrapper function for their stuff, which should be used because it keeps the transposing of the volume consistent. 

# Saving
Normal methods of saving tif files only support *unsigned* data (e.g. `uint16`) but our data is `int16`. The difference should be minimal, simply a matter of having negative values or not. But for consistency sake, and for a very slight speed increase, the custom `saveastiff()` function is used to write the data.