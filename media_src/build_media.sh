#!/bin/sh
# Rebuilds every media file of the prototype from the originals in media_src/.
# Needs: Python 3 with Pillow, ffmpeg, Node.js with Playwright. Run from the project folder
# while server.py is running (the video is recorded from the live prototype).
set -e
python3 media_src/make_map.py        # map_original.png -> static/img/map-420.webp, map-840.webp
python3 media_src/make_sound.py      # notify.wav -> static/media/notify.mp3 (64 kbit/s)

cp app.db app.db.bak                 # the recording submits one test report; put the database back after
node media_src/record_howto.js       # -> media_src/howto_frames/ (720 x 1280 PNG frames, about 10 s)
mv app.db.bak app.db

# frames -> lossless master video (FFV1 in MKV), all other versions are made from it
ffmpeg -y -loglevel error -f concat -i media_src/howto_frames/frames.txt -vf "fps=30,format=yuv420p" \
       -c:v ffv1 media_src/howto_master.mkv
rm -r media_src/howto_frames
RAW=media_src/howto_master.mkv
# master copy: H.264, CRF 12 (almost lossless) - used only by the /before page
ffmpeg -y -loglevel error -i $RAW -r 30 -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p \
       -movflags +faststart -an media_src/howto_original.mp4
# web copy: H.264 CRF 28 in MP4 (plays everywhere). The VP9/WebM copy is kept only for the
# format experiment in Part A2: it was not smaller for this screen recording, so the page uses MP4 only
ffmpeg -y -loglevel error -i $RAW -r 30 -c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p \
       -movflags +faststart -an static/media/howto.mp4
ffmpeg -y -loglevel error -i $RAW -r 30 -c:v libvpx-vp9 -crf 38 -b:v 0 -row-mt 1 -an media_src/howto_vp9.webm
# poster: the last frame with the green confirmation
ffmpeg -y -loglevel error -ss 9.3 -i $RAW -frames:v 1 media_src/howto-poster.png
# the video is shown at most 270 x 480 CSS px, so the poster is 540 x 960 (enough for 2x screens)
python3 -c "from PIL import Image; Image.open('media_src/howto-poster.png').resize((540, 960), Image.LANCZOS).save('static/media/howto-poster.webp', quality=75, method=6)"
rm media_src/howto_master.mkv        # the lossless master is very big; howto_original.mp4 is kept instead
echo "media rebuilt"
