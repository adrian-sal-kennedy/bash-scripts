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
#ffmpegBin="${HOME}/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffmpeg"
#ffprobeBin="${HOME}/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffprobe"
ffmpegBin=ffmpeg
ffprobeBin=ffprobe

# the below line is designed to be called by eval, and changed around depending on what the input is.
file=$1
inFile=$file
inpoint=$2
outpoint=$3

echo we\'re working with \"${file}\", I think.

if [ "${file##*.}" == "mov" ]
	then
	encodeCli='$ffmpegBin -nostdin -n -enable_drefs 1 -i "${inFile}"'
else
	encodeCli='$ffmpegBin -nostdin -n -i "${inFile}"'
fi

if [ "${file##*.}" == "vpy" ]
	then
	inFile="$(awk -F"'" '/source/ && !done {FS = "." ; print $2 ; done=1 }' "$1")"
	inFile="$(dirname "${file}")/$(basename "${inFile}")"
	if [ "${file##*.}" == "mov" ]
		then
		#encodeCli='vspipe "$file" - --y4m | $ffmpegBin -y -i - -enable_drefs 1 -i "${inFile}" '
		encodeCli='vspipe "$file" - --y4m | $ffmpegBin -nostdin -n -i - -enable_drefs 1 -i "${inFile}" '
	else
		#encodeCli='vspipe "$file" - --y4m | $ffmpegBin -y -i - -i "${inFile}"'
		encodeCli='vspipe "$file" - --y4m | $ffmpegBin -nostdin -n -i - -i "${inFile}"'
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
	ffprobe -select_streams a -show_streams -show_entries stream=index,channels:tags=:disposition= -i "${inFile}" 2>/dev/null >"${file}.astats"
fi
ffprobe -select_streams v -show_streams -show_entries -i "${inFile}" 2>/dev/null >"${file}.vstats"
ffprobe -show_streams -i "${inFile}" 2>/dev/null >"${file}.stats"
# Get timecode and reel_name if available.
# We check if there is a timecode field (on any stream! this does not handle caes with different timecodes per track but hopefully it shouldn't matter as we just copy the tags)
# If there is no timecode, we go to "creation_time" and pop that there. Canon DSLR's will write time-of-day to the second so we have very useful "timecodes" if we put them in a tag.

# Get timecode:
timecode="$(cat "${file}.stats" | awk -F= '/TAG:/ && /timecode/ && !done { print $2 ; done=1 }')"
echo is timecode really "$timecode"...?
if [ "x$timecode" == "x" ]
	then
		#below line is obsolete - we trim the numbers out using awk field separator now.
		#timecode="$(ffprobe -i "${inFile}" 2>&1 | awk '/creation_time/ && !done { print substr($3,12,8)":00" ;done=1 }')"
		timecode="$(cat "${file}.stats" | awk -F= '/TAG:/ && /creation_time/ && !done { print substr($2,12,8)":00" ; done=1 }')"
		# we fall back on zeroes if no creation_time exists either.
		if [ "x$timecode" == "x" ]
			then
			timecode=00:00:00:00
			echo No timecode found! Using 00:00:00:00.
			else
			echo Using creation_time as timecode. Set to $timecode
		fi
	else
	echo Found embedded timecode! Setting output to $timecode
fi
# Get reel_name:
reel_name="$(cat "${file}.stats" | awk -F= '/TAG:/ && /reel_name/ { print $2 ; done=1 }')"
if [ "x$reel_name" == "x" ]
	then
		reel_name=$(basename "${file%.*}")
		echo Setting reel_name to $reel_name as none set in source clip.
	else
	echo Found reel_name in source clip! Set to $reel_name
fi

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

framerateFrac=$(ffprobe -show_streams -i "${inFile}" 2>&1 | awk -F = '/avg_frame_rate/ && !done {print $2;done=1}')
h264_source=$(ffprobe -show_streams -i "${file}" 2>&1 | awk -F = '/codec_name=h264/ && !done {print $2;done=1}')
# we can detect any number of useful things here, and use them when generating the vpy script...

# tell us what we're dealing with:
# -----
echo Applying gain of ${ebur128}dB
echo Detected Frame rate of ${framerateFrac}fps

# ----------------Build command--------------------
#x264opts="-preset ultrafast -profile:v high422 -tune grain -x264-params "crf=10:tff=1:bframes=2:mbtree=1:rc_lookahead=24:deadzone-inter=6:deadzone-intra=3:qcomp=0.0:no-psy=1:vbv_maxrate=50000:vbv_bufsize=50000:keyint=24""
echo $h264_source >>test.txt
vidopts="-c:v prores -profile:v 0"
echo ${vidopts} >>test.txt
if [ "x${aMapString}" == "x" ]; then
	echo not h264, no audio.
	filter_cplx="-filter_complex [0:v]format=yuv422p10le,scale=out_range=tv[vout]${trim_vidonly}"
else
	echo not h264, has audio.
	filter_cplx="-filter_complex ${aFilter}asplit=2[aout][aout2];[aout]alimiter=${ebur128}dB:-1dB:-1dB:5:75[aout];[aout]atrim=start=0.005[aout];[0:v]format=yuv422p10le,scale=out_range=tv[vout]${trim}"
fi
vidmap="[vout]"

 if [ "x${aMapString}" == "x" ]
	then
# in queso no audio:
encodeCli+=' ${filter_cplx}
 -map ${vidmap} ${vidopts} -map_metadata 0
 -c:d copy -timecode "${timecode}" -metadata "reel_name"="$reel_name" -metadata "timecode"="${timecode}" "${file%.*}.mezzanine.mov" 1>&2'
#echo "$encodeCli" >test.txt
	else
encodeCli+=' ${filter_cplx}
 -map ${vidmap} ${vidopts}
 -map "[aout]" -map_metadata 0 -c:a pcm_s24le -map "[aout2]" -map_metadata 0 -c:a pcm_s24le -c:d copy -timecode "${timecode}" -metadata "reel_name"="$reel_name" -metadata "timecode"="${timecode}" "${file%.*}.mezzanine.mov" 1>&2'

# I use flac because it is smaller and lossless and fast and multichannel. Edit it in Reaper, which works in Windows, OSX and in Linux under wine.
# I can't use flac for more than 8 channels. oops. i need to sort out the best way to store multichannel.
#  single-stream is slightly better for editing, numbered discrete tracks better for management but nightmarish otherwise.
# FORMAT: mov corrupts the h264 stream somehow, mxf is weirdly extra slow on decode (VLC bug?), so we go mkv for now as it works. we can re-mux into anything.
echo $encodeCli >>test.txt
fi

eval $encodeCli
rm "${file}.astats"
rm "${file}.vstats"

#~/Sal/BATCHES/builds/ffmpeg-x264-10/bin/ffmpeg -y -i "World Peace and a Pony 1080p PRORES 422 HQ.mov" -an -c:v libx264 -preset ultrafast -tune grain -x264-params crf=2:bframes=2:keyint=12:interlaced=1:level=4.1:vbv-maxrate=25000:vbv-bufsize=25000 -vf "format=yuv422p10le" "World Peace and a Pony 1080p PRORES 422 HQ.mkv"
