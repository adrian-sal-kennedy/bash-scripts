#!/bin/bash

file=$1

echo "${file%.*}"
mkdir ./encodes

# IMPORTANT LINE detects the source video that the vpy is using.
# notes to myself when stealing this for future use:
# - when awk is invoked as a one-liner as below, FS must be set with -F, rather than inside the awk program with FS = ""
# - in case it's non-obvious, the "and not done, done = 1" malarky is so we only print the first occurrence, which in any sane vpy is what we want. Assume makes an ass out of u and me.
# - spaces between equals in bash are significant. don't use them or you'll be forever debuggering and not seeing your error.

inFile=$(awk -F"'" '/ffms2.Source/ && !done {FS = "." ; print $2 ; done=1 }' "$1")

# detect input clip properties:
# ------------------------------------
ebur128=$(ffmpeg -nostats -i "${inFile}" -filter_complex ebur128 -f null -vn - 2>&1 | awk '/I:  / {print -($2)-18}' | tail -n 1)
framerateFrac=$(ffprobe -show_streams -i "${inFile}" 2>&1 | awk -F = '/avg_frame_rate/ && !done {print $2;done=1}')
# we can detect any number of useful things here, and use them when generating the vpy script...

# tell us what we're dealing with:
# -----
echo Applying gain of ${ebur128}dB
echo Detected Frame rate of ${framerateFrac}fps

# ------------------------------------

