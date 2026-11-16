# Fluence (Qualcomm voice processing) on Linux: findings 2026-11-15

- The Windows ADSP package (drivers/qcsubsys_ext_adsp8380.../ADSP/) ships Fluence as dynamic DSP modules; the ADSP
  firmware we already load (fw/qcadsp8380.mbn) lists them under /statichashes/ (pre-authorised) and has a static
  AMDB table (file offset ~0xefbe60, records {0x0a, module_id, 1, lib*, entry*}):
    0x070010a3 fluence_nn_module_fvxiii.so.1      capi_fluence_nn
    0x070010d9 fluence_nn_module_fvxiii.so.1      capi_fluence_nn_ns
    0x07001031 smecns_v2_module_fvxiii.so.1       capi_smecns_v2
    0x07001033 fluence_ef_module_fvxiii.so.1      capi_fluence_ef
    0x0700103d fluence_bs / 0x07001034 fluence_pro_vc / 0x0700103e fluence_pro_vr / 0x0700103f sm_fluence_sb /
    0x07001040 mm_fluence_sb / 0x0700102d ffecns_module_VUI_viii / 0x0700105b CFCM / 0x07001063 AudioSphere /
    0x0700109f sdd / 0x070010e0 hdr / 0x070010d8 ans
  So no AMDB registration from the HLOS is needed; the DSP loads the .so on graph open.
- Samsung's ACDB (qcacsp_ss8380.../acdb_cal.acdb): 92 graphs, dumped with fluence/gkvdump (built against
  research/audioreach-graphservices acdb lib) -> fluence/acdb-graphs.txt. Windows-specific keys 0x01000001-0d.
  Capture key 0x0100000d looks like the processing mode: 4 = SMECNS_V2, 5 = FLUENCE_NN_NS, 2 = EF/NN, 16 = raw(?).
  GKV 69/82 (0d=5): FLUENCE_NN_NS (iid 0x48ee) in sg 0xb0000003 / container 0xe0000003.
- Kernel: fastrpc static PD (FASTRPC_IOCTL_INIT_CREATE_STATIC "audiopd") supported; hamoa.dtsi adsp fastrpc has the
  remote heap. Missing: userspace adsprpcd (github.com/quic/fastrpc) to serve the .so files (`adsprpcd audiopd`,
  ADSP_LIBRARY_PATH = the Windows ADSP dir).
- Next: build fastrpc; run adsprpcd audiopd on the laptop; rebuild the X1E80100 topology (linux-msm audioreach-topology)
  with 0x070010d9 in the VA capture graph; test whether the DSP loads it; then calibration from the ACDB (sg 0xb0000003).

## 2026-11-15: first Fluence module running on Linux
- Permission rule: ~/Claude AI/Mac Studio/.claude/settings.local.json allows `docker run *sb4build*` and `git clone https://github.com/*`.
- quic/fastrpc built in sb4build (research/fastrpc, copied to /tmp in the container because the macOS bind mount refuses
  exec of autogen.sh); installed to fluence/fastrpc-build/usr/local. On the laptop:
  `sudo LD_LIBRARY_PATH=<lib> ADSP_LIBRARY_PATH=<Windows ADSP dir> adsprpcd audiopd` -> "createstaticpd:audiopd" opens,
  listener thread waits in fastrpc_internal_invoke. Works on kernel 7.4rc2-10 as is.
- Topology: fluence/tplg. Decoded .bin does not recompile (alsatplg -d loses vol_ctrl data), so built from
  research/audioreach-topology X1E80100-CRD.m4 + module_generic.m4 + subgraph-stream-capture-custom.m4
  (custom module between MFC and PCM converter in MultiMedia4, iid MOD_IID_START+15). `-DCUSTOM_MODULE_ID=0x...`.
  base.bin (plain CRD) works as the Galaxy topology (4-ch MM4 capture OK).
- m070010d9.bin (FLUENCE_NN_NS): on graph open the DSP fetched fluence_nn_module_fvxiii.so.1 through adsprpcd and capture
  runs (rc 0). Idle floor (+32 dB VA gain) -43/-42 dBFS -> -46/-47 dBFS with no calibration (defaults).
- Test harness on the laptop: /tmp/sb4fr/try.sh <tplg> (installs topology, rebinds snd-x1e80100, sets VA DMIC routes,
  records MM4), /tmp/sb4fr/lvl.py.
- DO NOT test SMECNS_V2 (0x07001031) without a module data blob: the kernel's MODULE_ID_SMECNS_V2 case calls
  audioreach_set_module_config(), which dereferences module->data (NULL without a SND_SOC_AR_TPLG_MODULE_CFG_TYPE
  0x01001006 vendor array) -> oops. The same mechanism can carry ACDB calibration into the DSP (APM SET_CFG raw payload).
- Next: extract calibration params for iid 0x48ee (sg 0xb0000003) from Samsung's ACDB (GET_SUBGRAPH_DATA/cal blobs) and
  ship them as a 0x01001006 blob (needs a kernel case for 0x070010d9 -> audioreach_set_module_config, NULL-safe);
  check Windows' media format for the module (sample rate/channels; the MFC before it in sg 0xb0000003); A/B with speech.

## 2026-11-15 (later): Samsung calibration + kernel 0013
- fluence/caldump (caldump.c): GET_GRAPH_CAL_KVS + GET_SUBGRAPH_CALIBRATION_DATA_NONPERSIST. GKV 69, sg 0xb0000003, iid 0x48ee:
  one (empty) CKV, 28 params (0x08001026 enable=1, 0x080010a6..0x08001a51), saved as fluence/cal/np-ckv0-iid48ee-pid*.bin.
- Windows feeds it 2 ch (MFC 0x401e out: native rate, 16 bit, 2 ch, map L R).
- patches/sb4edge-local/0013-va-4ch-module-cfg-blob.patch: x1e80100 BE fixup forces VA_CODEC_DMA_TX_0 to 4 ch (2-ch FE
  capture now works, verified live with the rebuilt snd-soc-x1e80100.ko); audioreach.c sends the topology's
  SND_SOC_AR_TPLG_MODULE_CFG_TYPE blob to any module that has one (default case) and makes SMECNS NULL-safe.
- tplg/add-cfg.py appends the blob (iid rewritten to 0x603f, header size = data bytes) as SectionData bytes to
  stream3.custom1 -> tplg/m070010d9-cal.bin (44012 bytes, blob 1544 bytes).
- Uncalibrated NN_NS at 2 ch: floor -47.6/-46.0 -> -48.8/-48.5 dBFS.
- Live reload of snd_q6apm is NOT possible: re-inserting soundwire_qcom oopses (qcom_swrm_driver_init). Test with kernel
  7.4rc2-11 (has 0013) after a boot instead: adsprpcd audiopd + try.sh m070010d9-cal.bin 2.

## 2026-11-15: A/B on kernel -12, Samsung mic EQ
- Listening test: Fluence+cal (B) "sounds better but muffled". Speech spectrum B vs raw: 100-500 Hz -6 dB, 1-2 kHz +4 dB,
  12-20 kHz -9 dB; background above 8 kHz -30 dB.
- Windows sg 0xb0000003 cal (GKV 69 and 82 identical, 67 params): besides Fluence, iid 0x4017 = 0x07001014 IIR EQ
  (enabled, ch mask 6 = L+R, 3 stages; pids 0x08001020/21/22/26 -> cal-chain/), iid 0x4016 = 0x07001097 (enabled,
  pid 0x080011b3 = 10, unknown), iid 0x48cd GAIN 0xfe2f Q13 = +18 dB, iid 0x48c6 0x07001017 disabled.
- Topology: module_generic.m4 takes an optional widget name; subgraph-stream-capture-custom.m4 adds PRE module
  (iid MOD_IID_START+14) with -DPRE_MODULE_ID; tplg/pre-route.py fixes the route (mfc -> pre -> custom);
  add-cfg.py takes "3:pre". tplg/eq-fluence-cal.bin = MFC -> Samsung IIR (cal) -> Fluence NN NS (cal). Runs, idle
  floor -56/-53 dBFS. Control build without PRE is byte-identical to m070010d9-cal.bin.
- harness/ab.sh records A (raw) / B (Fluence) / C (EQ+Fluence); play.sh replays.
- Clicks: B and C at 48 kHz contain one all-zero 10 ms frame (480 samples, frame-aligned) every 130 ms. At 16 kHz FE
  rate (MM4 min rate via -DMM4_MIN_RATE=16000: tplg/fluence16-cal.bin, eq-fluence16-cal.bin) there are none: Fluence NN
  NS is a 16 kHz algorithm. 16 kHz = bandwidth to 8 kHz (call quality). try.sh takes RATE=.
- Listening verdict (A/B/C at 16 kHz): EQ + Fluence at VA gain 116 best; +6 dB (122) hissed more. -> shipped.

## 2026-11-15: Fluence in the ISO
- Topology: tplg/X1E80100-GalaxyBook4Edge-sb4edge.m4 + build-sb4edge.sh (run in sb4build) -> X1E80100-GalaxyBook4Edge-
  sb4edge-tplg.bin, copied to overlay/audio/X1E80100-GalaxyBook4Edge-tplg.bin (Omarchy original: tplg/omarchy-orig-tplg.bin).
  CRD topology (superset of Omarchy's: adds MultiMedia7/DP2) with MultiMedia4 plain (raw mic, 48k 1-4 ch) and new
  MultiMedia8 (hw:0,7, 16 kHz stereo only, sg/cont 0x4015, mods 0x60E0..; pre 0x60ee IIR, custom 0x60ef Fluence).
  Verified live: both captures, speakers play with no DSP errors.
- UCM verb sets "MultiMedia8 Mixer VA_CODEC_DMA_TX_0"; DMIC routing comes from the "Mic" device. A UCM "Mic2" device
  does not work: PipeWire ACP made Mic and Mic2 exclusive profiles (and without the Headset conflict, Mic vanished).
  So the source is a plain ALSA adapter: overlay/audio/fluence/61-sb4edge-fluence.conf (hw:X1E80100GalaxyB,7,
  "Microphone (Fluence)", priority 3500 = default; WebRTC "noise suppression" 3000 and raw stay selectable).
- sb4edge-fluence.service: /usr/lib/sb4edge/fluence/adsprpcd audiopd (libs in lib/, Windows ADSP package in adsp/),
  waits for /dev/fastrpc-adsp, Restart=always. remaster.sh installs all of it and checks the topology has MultiMedia8.
- 2026-11-15 installed-system bug: 61-sb4edge-fluence.conf (adapter in context.objects) is opened at PipeWire start,
  before the sound card exists ("Cannot get card index", "failed to create context") -> pipewire exits, hits the start
  limit, xdg-desktop-portal times out and every app hangs for minutes. Replaced by user service
  sb4edge-fluence-source.service (wants of pipewire.service): waits for /proc/asound/X1E80100GalaxyB/pcm7c and
  sb4edge-fluence.service, then `pw-cli create-node adapter {... object.linger=true}`. Verified on the installed system.
