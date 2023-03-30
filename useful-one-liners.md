## Transcode all wavs in current dir to flac (and delete wav if successful):
`find $PWD -iname "*.wav" | while read file; do ffmpeg -n -nostdin -i "$file" -c:a flac "${file%%.*}.flac" && rm "$file"; done`
