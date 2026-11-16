import sys
p=sys.argv[1]; s=open(p).read()
a="""static int msm_dp_display_process_hpd_high(struct msm_dp_display_private *dp)
{"""
assert s.count(a)==1
s=s.replace(a,"""/*
 * sb4edge: plain I2C-over-AUX EDID block read. drm_edid_read_ddc() first probes the DDC bus with a 1-byte
 * read, which fails through a DP-to-HDMI adapter behind USB-C although full block reads work.
 */
static int msm_dp_read_edid_block(void *data, u8 *buf, unsigned int block, size_t len)
{
	struct i2c_adapter *ddc = data;
	u8 seg = block >> 1, off = (block & 1) * EDID_LENGTH;
	struct i2c_msg m[3] = {
		{ .addr = 0x30, .flags = 0, .len = 1, .buf = &seg },
		{ .addr = 0x50, .flags = 0, .len = 1, .buf = &off },
		{ .addr = 0x50, .flags = I2C_M_RD, .len = len, .buf = buf },
	};
	int n = seg ? 3 : 2, i;

	for (i = 0; i < 3; i++)
		if (i2c_transfer(ddc, &m[3 - n], n) == n)
			return 0;
	return -EIO;
}

"""+a)
b="""	drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	/* sb4edge: an adapter that just woke up can need a moment more for the monitor's EDID */
	for (int i = 0; !drm_edid && drm_dp_is_branch(dpcd) && i < 5; i++) {
		msleep(100);
		drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	}
"""
assert s.count(b)==1
s=s.replace(b,"""	drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	if (!drm_edid && drm_dp_is_branch(dpcd)) {
		drm_edid = drm_edid_read_custom(connector, msm_dp_read_edid_block, &dp->aux->ddc);
		drm_info(dp->drm_dev, "sb4edge: branch device EDID read without DDC probe: %s\\n",
			 drm_edid ? "ok" : "failed");
	}
""")
open(p,"w").write(s)
