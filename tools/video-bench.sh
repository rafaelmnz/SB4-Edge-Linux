#!/bin/bash
# Hardware (Iris, V4L2) vs software video encode/decode/transcode on the Galaxy Book4 Edge.
# Synthetic moving SMPTE bars (easy content: software decoders look better than on real video).
# Usage: tools/video-bench.sh   (needs gstreamer1.0-plugins-{good,bad,ugly}, gstreamer1.0-libav, bc; ~3 GB in /var/tmp)
D=/var/tmp/vbench; mkdir -p $D; cd $D
G="gst-launch-1.0 -q"
run() { # label frames pipeline...
  local l=$1 n=$2; shift 2
  local t0=$(date +%s.%N); local c0=$(awk '{print $14+$15+$16+$17}' /proc/self/stat)
  /usr/bin/time -f "%e %P" -o /tmp/vb.t timeout 600 $G "$@" >/dev/null 2>&1; rc=$?
  read e p < /tmp/vb.t
  [ $rc = 0 ] && printf "%-46s %7.1f fps  %6s CPU  (%ss)\n" "$l" $(echo "$n / $e" | bc -l) "$p" "$e" || printf "%-46s FAILED rc=%s\n" "$l" $rc
}
R1="filesrc location=$D/src1080.yuv ! rawvideoparse width=1920 height=1080 format=i420 framerate=30/1"
N1="filesrc location=$D/src1080nv12.yuv ! rawvideoparse width=1920 height=1080 format=nv12 framerate=30/1"
N4="filesrc location=$D/src2160nv12.yuv ! rawvideoparse width=3840 height=2160 format=nv12 framerate=30/1"
R4="filesrc location=$D/src2160.yuv ! rawvideoparse width=3840 height=2160 format=i420 framerate=30/1"
[ -f src1080.yuv ] || $G videotestsrc num-buffers=300 pattern=smpte horizontal-speed=6 ! video/x-raw,width=1920,height=1080,format=I420,framerate=30/1 ! filesink location=src1080.yuv
[ -f src2160.yuv ] || $G videotestsrc num-buffers=120 pattern=smpte horizontal-speed=12 ! video/x-raw,width=3840,height=2160,format=I420,framerate=30/1 ! filesink location=src2160.yuv
[ -f src1080nv12.yuv ] || $G videotestsrc num-buffers=300 pattern=smpte horizontal-speed=6 ! video/x-raw,width=1920,height=1080,format=NV12,framerate=30/1 ! filesink location=src1080nv12.yuv
[ -f src2160nv12.yuv ] || $G videotestsrc num-buffers=120 pattern=smpte horizontal-speed=12 ! video/x-raw,width=3840,height=2160,format=NV12,framerate=30/1 ! filesink location=src2160nv12.yuv
echo "== ENCODE (raw frames; hardware encoders take NV12, software ones I420)"
run "H.264 1080p  sw x264 veryfast"  300 $R1 ! x264enc speed-preset=veryfast bitrate=8000 ! h264parse ! mp4mux ! filesink location=sw264_1080.mp4
run "H.264 1080p  hw v4l2h264enc"    300 $N1 ! v4l2h264enc ! h264parse ! mp4mux ! filesink location=hw264_1080.mp4
run "H.264 4K     sw x264 veryfast"  120 $R4 ! x264enc speed-preset=veryfast bitrate=30000 ! h264parse ! mp4mux ! filesink location=sw264_2160.mp4
run "H.264 4K     hw v4l2h264enc"    120 $N4 ! v4l2h264enc ! h264parse ! mp4mux ! filesink location=hw264_2160.mp4
run "HEVC  4K     sw x265 veryfast"  120 $R4 ! x265enc speed-preset=veryfast bitrate=20000 ! h265parse ! matroskamux ! filesink location=sw265_2160.mkv
run "HEVC  4K     hw v4l2h265enc"    120 $N4 ! v4l2h265enc ! h265parse ! matroskamux ! filesink location=hw265_2160.mkv
run "VP9   1080p  sw vp9enc rt"      300 $R1 ! vp9enc deadline=1 cpu-used=8 threads=12 ! webmmux ! filesink location=sw_vp9_1080.webm
run "AV1   1080p  sw svtav1enc p10"  300 $R1 ! svtav1enc preset=10 ! av1parse ! webmmux ! filesink location=sw_av1_1080.webm
echo "== DECODE (software-encoded files)"
run "H.264 1080p  sw avdec_h264"     300 filesrc location=sw264_1080.mp4 ! qtdemux ! h264parse ! avdec_h264 ! fakesink sync=false
run "H.264 1080p  hw v4l2h264dec"    300 filesrc location=sw264_1080.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! fakesink sync=false
run "H.264 4K     sw avdec_h264"     120 filesrc location=sw264_2160.mp4 ! qtdemux ! h264parse ! avdec_h264 ! fakesink sync=false
run "H.264 4K     hw v4l2h264dec"    120 filesrc location=sw264_2160.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! fakesink sync=false
run "HEVC  4K     sw avdec_h265"     120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! avdec_h265 ! fakesink sync=false
run "HEVC  4K     hw v4l2h265dec"    120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! v4l2h265dec ! fakesink sync=false
run "VP9   1080p  sw avdec_vp9"      300 filesrc location=sw_vp9_1080.webm ! matroskademux ! vp9parse ! avdec_vp9 ! fakesink sync=false
run "VP9   1080p  hw v4l2vp9dec"     300 filesrc location=sw_vp9_1080.webm ! matroskademux ! vp9parse ! v4l2vp9dec ! fakesink sync=false
run "AV1   1080p  sw av1dec (libaom)" 300 filesrc location=sw_av1_1080.webm ! matroskademux ! av1parse ! av1dec ! fakesink sync=false
run "AV1   1080p  hw v4l2av1dec"     300 filesrc location=sw_av1_1080.webm ! matroskademux ! av1parse ! v4l2av1dec ! fakesink sync=false
echo "== TRANSCODE"
run "4K HEVC -> 4K H.264      sw->sw" 120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! avdec_h265 ! x264enc speed-preset=veryfast bitrate=30000 ! h264parse ! mp4mux ! filesink location=t1.mp4
run "4K HEVC -> 4K H.264      hw->hw" 120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! v4l2h265dec ! v4l2h264enc ! h264parse ! mp4mux ! filesink location=t2.mp4
run "4K HEVC -> 1080p H.264   sw->sw" 120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! avdec_h265 ! videoscale ! video/x-raw,width=1920,height=1080 ! x264enc speed-preset=veryfast bitrate=8000 ! h264parse ! mp4mux ! filesink location=t3.mp4
run "4K HEVC -> 1080p H.264   hw (cpu scale)" 120 filesrc location=sw265_2160.mkv ! matroskademux ! h265parse ! v4l2h265dec ! videoconvert ! videoscale ! video/x-raw,width=1920,height=1080,format=NV12 ! v4l2h264enc ! h264parse ! mp4mux ! filesink location=t4.mp4
ls -la $D/*.mp4 $D/*.mkv $D/*.webm | awk '{print $5, $9}'
