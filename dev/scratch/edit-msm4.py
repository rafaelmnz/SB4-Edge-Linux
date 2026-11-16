import sys
p=sys.argv[1]; s=open(p).read()
a="""	for (i = 0; i < 3; i++)
		if (i2c_transfer(ddc, &m[3 - n], n) == n)
			return 0;
	return -EIO;"""
assert s.count(a)==1
s=s.replace(a,"""	for (i = 0; i < 3; i++)
		if (i2c_transfer(ddc, &m[3 - n], n) == n)
			return 0;
	if (seg) {
		/*
		 * The adapter NACKs the E-DDC segment pointer (0x30), so blocks 2+ (HF-EEODB EDIDs, e.g. the
		 * Odyssey G95NC: 384 bytes) cannot be read. Hand back a zero block: DRM drops it as invalid
		 * and keeps the base and CTA blocks instead of failing the whole EDID.
		 */
		pr_info_once("sb4edge: DP adapter rejects EDID segment pointer, ignoring blocks 2+\\n");
		memset(buf, 0, len);
		return 0;
	}
	return -EIO;""")
a2="""/*
 * sb4edge: plain I2C-over-AUX EDID block read. drm_edid_read_ddc() first probes the DDC bus with a 1-byte
 * read, which fails through a DP-to-HDMI adapter behind USB-C although full block reads work.
 */"""
assert s.count(a2)==1
s=s.replace(a2,"""/*
 * sb4edge: EDID block reader for DP branch devices (DP-to-HDMI adapters) that cannot read EDID blocks
 * past the first segment; see below.
 */""")
b="""		drm_info(dp->drm_dev, "sb4edge: branch device EDID read without DDC probe: %s\\n","""
assert s.count(b)==1
s=s.replace(b,"""		drm_info(dp->drm_dev, "sb4edge: branch device EDID (first segment only): %s\\n",""")
open(p,"w").write(s)
