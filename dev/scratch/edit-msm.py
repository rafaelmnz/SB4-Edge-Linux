import sys
p=sys.argv[1]; s=open(p).read()
assert "sb4edge: DP-to-HDMI" not in s
a="""	dp->link->lttpr_count = msm_dp_display_lttpr_init(dp, dpcd);
"""
assert s.count(a)==1
s=s.replace(a, a+"""
	/*
	 * sb4edge: a DP-to-HDMI adapter (branch device) behind USB-C answers DPCD while powered down, but
	 * counts its monitor and passes the EDID through only once it is in D0. Wake it and wait for the
	 * sink before reading the link caps (sink count) and the EDID.
	 */
	if (drm_dp_is_branch(dpcd)) {
		int i;

		drm_dp_dpcd_write_byte(dp->aux, DP_SET_POWER, DP_SET_POWER_D0);
		for (i = 0; i < 20 && drm_dp_read_sink_count(dp->aux) <= 0; i++)
			msleep(50);
	}
""",1)
b="""	drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	drm_edid_connector_update(connector, drm_edid);
"""
assert s.count(b)==1
s=s.replace(b,"""	drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	/* sb4edge: an adapter that just woke up can need a moment more for the monitor's EDID */
	for (int i = 0; !drm_edid && drm_dp_is_branch(dpcd) && i < 5; i++) {
		msleep(100);
		drm_edid = drm_edid_read_ddc(connector, &dp->aux->ddc);
	}
	drm_edid_connector_update(connector, drm_edid);
""",1)
open(p,"w").write(s)
