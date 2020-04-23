#!/bin/bash
scripts="${HOME}/Desktop/Sal/BATCHES/bash-tool-scripts/vpy"

# it's likely i'll have to include some kind of check in here to ensure the generated file actually returns video...

echo $1

# if [[ "$(echo ${1: -3} | awk '{print toupper($0)}')" == "MOV" ]]
# 	then
# 	echo i got a quicktime!
# 	cat $scripts/vs-template-Quicktime.vpy | sed -e "s@SOURCE@$1@g" > "${1%.*}.vpy"
# else
# 	echo i got something other than a quicktime!
# 	cat $scripts/vs-template-dvd.vpy | sed -e "s@SOURCE@$1@g" > "${1%.*}.vpy"
# fi

case "$(echo ${1: -3} | awk '{print toupper($0)}')" in
	"MOV" | "MP4") echo "I got a Quicktime/mp4!"
	cat $scripts/vs-QT-uprez-denoise.vpy | sed -e "s@SOURCE@$1@g" > "${1%.*}.vpy" ;;
	*) echo "I got something other than a Quicktime/mp4!"
 	cat $scripts/vs-DVD-uprez-denoise.vpy | sed -e "s@SOURCE@$1@g" > "${1%.*}.vpy" ;;
esac

vsedit "${1%.*}.vpy"
