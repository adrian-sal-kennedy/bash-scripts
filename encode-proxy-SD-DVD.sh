#!/bin/bash
# This script encodes a source file from either .vpy (vapoursynth) or any ffmpeg supported format into a 10-bit 4:2:2 h.264 file in high bitrate (25mbps)
# for later use in generating encodes for streaming. It is designed to be run on an ubuntu VM that has the following installed:
# - x264 (8 bit and 10 bit builds)
# - ffmpeg (2 separate builds, built with x264 8 and 10-bit, fdk-aac, x265, and all other options in --enable-everything --enable-gpl --enable-version3 --enable-nonfree)
# - vapoursynth
# - awk
# - tail (FIXME: this could be got rid of and folded into the preceding awk line)
# This virtual machine will be buildable using a stock ubuntu iso and a shell script to pull everything from git and build (this doesn't exist yet).
# -------------------------------

# -------- FIXME ---------
# I think it might be best to set in and out points as part of the argument for the file they belong to:
# test.mov:10.0:40.0
# instead of:
# test.mov 10.0 40.0
# this way our positional parameters are more robust - i can chop them up in here using string magic and we can use the positional parameters for options or destinations.

# -------- Set up helper functions ---------

# go write some if you need 'em.

# -------- Set up paths ----------
ffmpegBin=ffmpeg #"${HOME}/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffmpeg"
ffprobeBin=ffprobe #"${HOME}/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffprobe"
# the below line is designed to be called by eval, and changed around depending on what the input is.
file=$1
inFile=$file
inpoint=$2
outpoint=$3

echo we\'re working with \"${file}\", I think.
if [ -s "${file%.*}.mezzanine.mxf" ]
	then
	echo file "${file%.*}.mezzanine.mxf" exists! bailing out!
	exit 1;
fi 
if [ -s "${file%.*}.mezzanine.MOS.mxf" ]
	then
	echo file "${file%.*}.mezzanine.mxf" exists! bailing out!
	exit 1;
fi 


# IMPORTANT LINE detects the source video that the vpy is using.
# notes to myself when stealing this for future use:
# - when awk is invoked as a one-liner as below, FS must be set with -F, rather than inside the awk program with FS = ""
# - in case it's non-obvious, the "and not done, done = 1" malarky is so we only print the first occurrence, which in any sane vpy is what we want. Assume makes an ass out of u and me.
# - spaces between equals in bash are significant. don't use them or you'll be forever debuggering and not seeing your error.

# EXTRACTING FILE INFO:
# assume foo = blah.poo.bar
# ${foo#*.} returns poo.bar
# ${foo##*.} returns bar. this means we can extract the file extension or anything between a leading dot (like file.720p25.stereo.ebu-15.mov)

#if [ "${file##*.}" == "mov" ]
#	then
#	encodeCli='$ffmpegBin -enable_drefs 1 -y -i "${inFile}"'
#else
#	encodeCli='$ffmpegBin -y -i "${inFile}"'
#fi

if [ "${file##*.}" == "mov" ]
	then
	encodeCli='$ffmpegBin -err_detect ignore_err -nostdin -enable_drefs 1 -i "${inFile}"'
else
	encodeCli='$ffmpegBin -err_detect ignore_err -nostdin -i "${inFile}"'
fi

if [ "${file##*.}" == "vpy" ]
	then
	inFile="$(awk -F"'" '/source/ && !done {FS = "." ; print $2 ; done=1 }' "$1" )"
	inFile="$(dirname "${file}")/$(basename "${inFile}" )"
	if [ "${file##*.}" == "mov" ]
		then
		#encodeCli='vspipe "$file" - --y4m | $ffmpegBin -y -i - -enable_drefs 1 -i "${inFile}" '
		encodeCli='vspipe "$file" - --y4m | $ffmpegBin -nostdin -i - -enable_drefs 1 -i "${inFile}" '
	else
		#encodeCli='vspipe "$file" - --y4m | $ffmpegBin -y -i - -i "${inFile}"'
		encodeCli='vspipe "$file" - --y4m | $ffmpegBin -nostdin -i - -i "${inFile}"'
	fi
	echo $inFile
	echo $encodeCli
fi
# detect audio and handle in/out points specified on command line.

if [ "x$3" == "x" ]
	then
	if [ "x$2" == "x" ]
	then
	trim_audio=""
	ebu_trim_audio="anull[aout]"
	trim_video=""
	trim_vidonly=""
	echo no trim value!
    else
    trim_audio="atrim=start=$2[aout]"
	ebu_trim_audio=$trim_audio
    trim_video=";[vout]trim=start=$2[vout];[aout]"
	trim_vidonly=";[vout]trim=start=$2[vout]"
    fi
else
	trim_audio="atrim=start=$2:end=$3[aout]"
	ebu_trim_audio=$trim_audio
	trim_video=";[vout]trim=start=$2:end=$3[vout];[aout]"
	trim_vidonly=";[vout]trim=start=$2:end=$3[vout]"
fi
trim=${trim_video}${trim_audio}

# detect input clip properties:
# ------------------------------------
# discover all of the audio (discrete, multichannel, etc) and merge them into 1 multichannel track for editing.
# while we're being non-standard, we might as well use flac for the audio and save some space.

if [ ! -s "${file}.astats" ]
	then
	${ffprobeBin} -select_streams a -show_streams -show_entries stream=index,channels:tags=:disposition= -i "${inFile}" 2>/dev/null >"${file}.astats"
fi
${ffprobeBin} -select_streams v -show_streams -show_entries -i "${inFile}" 2>/dev/null >"${file}.vstats"
# stream=index,channels:tags=:disposition=
aTracks=$(awk -F"=" '/channels/ {print $2}' "${file}.astats" | wc -l | tr -d ' ')
aChannels=$(awk -F"=" '/channels/ {sum+=$2} END {print sum}' "${file}.astats")
echo $aChannels total audio channels across $aTracks tracks.
aMapString=$(awk -F"=" '/index/ {idx = (idx)"[0:"($2)"]"} END {print idx}' "${file}.astats")
# if we're coming from a vpy, change the mapstring to the first file, not the zeroth.
# we will want to make this "+1" with awk or something because we want to eventually support audio files on the CLI.

if (( ${aTracks} > 1 ))
	then
	aFilter="${aMapString}amerge=inputs=${aTracks}[aout];[aout]"
else
	aFilter="${aMapString}"
fi
echo $aTracks audio tracks.
echo constructed map string: $aMapString
echo
if [ -s "${file}.ebur128" ]
	then
  ebur128=$(<"${file}.ebur128")
  echo working with an existing ebu r-128 value...
	else
  echo 'Scanning '${file} 'for EBU-R128 loudness level. Please wait...'
  ebur128=$($ffmpegBin -nostats -i "${inFile}" -ac 2 -filter_complex "${aFilter}${ebu_trim_audio};[aout]ebur128[aout]" -map "[aout]" -f null -vn - 2>&1 | awk '/I: / {print -($2)-18}' | tail -n 1) && echo ${ebur128} > "${file}.ebur128"
  if [ "x${aMapString}" == "x" ]
   	then
  	ebur128=0
  fi
 fi
echo

if [ $( echo $ebur128 \> 20 | bc -l) ]
	then
	ebur128=0
	echo EBU-R128 ignored, as volume is too low to be meaningful. Applying gain of ${ebur128}dB to output.
	else
	echo EBU-R128 found! Applying gain of ${ebur128}dB to output.
fi

echo Press the Anykey to continue...

[ "${file##*.}" == "vpy" ] && aFilter=$(echo ${aFilter} | sed -e 's/\[0\:/\[1\:/g')
#read -p "$*"

framerateFrac=$($ffprobeBin -show_streams -i "${inFile}" 2>&1 | awk -F = '/avg_frame_rate/ && !done {print $2;done=1}')
h264_source=$($ffprobeBin -show_streams -i "${file}" 2>&1 | awk -F = '/codec_name=h264/ && !done {print $2;done=1}')
echo $ffprobeBin -show_streams -i "${file}" 2>&1 >test.txt
# we can detect any number of useful things here, and use them when generating the vpy script...

# tell us what we're dealing with:
# -----
echo Applying gain of ${ebur128}dB
echo Detected Frame rate of ${framerateFrac}fps

# ----------------Build command--------------------
#x264opts="-preset ultrafast -profile:v high422 -tune grain -x264-params "crf=10:tff=1:bframes=2:mbtree=1:rc_lookahead=24:deadzone-inter=6:deadzone-intra=3:qcomp=0.0:no-psy=1:vbv_maxrate=50000:vbv_bufsize=50000:keyint=24""
echo $h264_source >>test.txt
if [ "x${h264_source}" == "x" ] || [ "x$2" != "x" ]; then
	vidopts="-c: copy -c:v mpeg2video -q:v 1 -maxrate 8500k -bufsize 4000k"
	echo ${vidopts} >>test.txt
	if [ "x${aMapString}" == "x" ]; then
		echo not h264, no audio.
		filter_cplx="-filter_complex [0:v]format=yuv420p,scale=w=1050:h=576:force_original_aspect_ratio=1,scale=w=704:h=576,pad=720:576:(ow-iw)/2:(oh-ih)/2,colormatrix=bt709:bt601,setsar=sar=64/45[vout]${trim_vidonly}"
	else
		echo not h264, has audio.
		filter_cplx="-filter_complex ${aFilter}alimiter=${ebur128}dB:-1dB:-1dB:5:75[aout];[aout]atrim=start=0.005[aout];[0:v]format=yuv420p,scale=w=1050:h=576:force_original_aspect_ratio=1,scale=w=704:h=576,pad=720:576:(ow-iw)/2:(oh-ih)/2,colormatrix=bt709:bt601,setsar=sar=64/45[vout]${trim}"
	fi
	vidmap="[vout]"
else
	vidopts="-c: copy -c:v mpeg2video -q:v 1 -maxrate 8500k -bufsize 4000k"
	echo ${vidopts} >>test.txt
	if [ "x${aMapString}" == "x" ]; then
		filter_cplx=
		echo h264, no audio.
	else
		echo h264, has audio.
		filter_cplx="-filter_complex ${aFilter}alimiter=${ebur128}dB:-1dB:-1dB:5:75[aout];[aout]atrim=start=0.005[aout];[0:v]format=yuv420p,scale=w=1050:h=576:force_original_aspect_ratio=1,scale=w=704:h=576,pad=720:576:(ow-iw)/2:(oh-ih)/2,colormatrix=bt709:bt601,setsar=sar=64/45[vout]${trim}"
	fi
	vidmap="[vout]"
	#vidmap="0:v"
fi

 if [ "x${aMapString}" == "x" ]
	then
# in queso no audio:
encodeCli+=' ${filter_cplx}
 -map ${vidmap} ${vidopts}
 -c:d copy "${file%.*}.mezzanine.MOS.mxf"'
echo $encodeCli >test.txt
	else
encodeCli+=' ${filter_cplx}
 -map ${vidmap} ${vidopts}
 -map "[aout]" -c:a pcm_s24le -c:d copy "${file%.*}.mezzanine.mxf"'
# I use flac because it is smaller and lossless and fast and multichannel. Edit it in Reaper, which works in Windows, OSX and in Linux under wine.
# I can't use flac for more than 8 channels. oops. i need to sort out the best way to store multichannel.
#  single-stream is slightly better for editing, numbered discrete tracks better for management but nightmarish otherwise.
# FORMAT: mov corrupts the h264 stream somehow, mxf is weirdly extra slow on decode (VLC bug?), so we go mkv for now as it works. we can re-mux into anything.
fi

eval $encodeCli
rm "${file}.astats"
rm "${file}.vstats"
rm "${file}.ebur128"

#~/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffmpeg -y -i "World Peace and a Pony 1080p PRORES 422 HQ.mov" -an -c:v libx264 -preset ultrafast -tune grain -x264-params crf=2:bframes=2:keyint=12:interlaced=1:level=4.1:vbv-maxrate=25000:vbv-bufsize=25000 -vf "format=yuv422p10le" "World Peace and a Pony 1080p PRORES 422 HQ.mkv"
