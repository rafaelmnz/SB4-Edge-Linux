import sys
p=sys.argv[1]; s=open(p).read()
a="""		drm_dp_dpcd_write_byte(dp->aux, DP_SET_POWER, DP_SET_POWER_D0);
		for (i = 0; i < 20 && drm_dp_read_sink_count(dp->aux) <= 0; i++)
			msleep(50);
	}
"""
assert s.count(a)==1
s=s.replace(a,"""		int w = drm_dp_dpcd_write_byte(dp->aux, DP_SET_POWER, DP_SET_POWER_D0), sc = 0;

		for (i = 0; i < 20 && (sc = drm_dp_read_sink_count(dp->aux)) <= 0; i++)
			msleep(50);
		pr_info("sb4dbg: branch: set_power ret %d, sink count %d after %d tries, lttpr %d\\n", w, sc, i,
			dp->link->lttpr_count);
	}
""")
b="""	drm_edid_connector_update(connector, drm_edid);

	if (!drm_edid) {"""
assert s.count(b)==1
s=s.replace(b,"""	drm_edid_connector_update(connector, drm_edid);

	if (!drm_edid) {
		u8 off = 0, hdr[8] = {};
		struct i2c_msg m[2] = {
			{ .addr = 0x50, .flags = 0, .len = 1, .buf = &off },
			{ .addr = 0x50, .flags = I2C_M_RD, .len = 8, .buf = hdr },
		};
		int t = i2c_transfer(&dp->aux->ddc, m, 2);

		pr_info("sb4dbg: edid raw i2c ret %d: %*ph, sink count %d, link connected %u\\n", t, 8, hdr,
			drm_dp_read_sink_count(dp->aux), msm_dp_aux_is_link_connected(dp->aux));
	}
	if (!drm_edid) {""")
open(p,"w").write(s)
