#!/bin/bash

file=$1

echo "${file%.*}"

# IMPORTANT LINE detects the source video that the vpy is using.
# notes to myself when stealing this for future use:
# - when awk is invoked as a one-liner as below, FS must be set with -F, rather than inside the awk program with FS = ""
# - in case it's non-obvious, the "and not done, done = 1" malarky is so we only print the first occurrence, which in any sane vpy is what we want. Assume makes an ass out of u and me.
# - spaces between equals in bash are significant. don't use them or you'll be forever debuggering and not seeing your error.

#inFile=$(awk -F"'" '/ffms2.Source/ && !done {FS = "." ; print $2 ; done=1 }' "$1")
# this file may be a movie file with video and audio. it may have several audio tracks. it may be video only. we need to test it and give the user an option of choosing another track or file.

# ------------------------------------

ffprobe -show_streams -i "${file}" &> "${file}.stats"
sed -n "/Audio:/p" "${file}.stats" | wc -l