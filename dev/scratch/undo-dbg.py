import sys,re
p=sys.argv[1]; s=open(p).read()
i=s.index("		int w = drm_dp_dpcd_write_byte"); j=s.index("lttpr_count);\n",i)+len("lttpr_count);\n")
s=s[:i]+"""		drm_dp_dpcd_write_byte(dp->aux, DP_SET_POWER, DP_SET_POWER_D0);
		for (i = 0; i < 20 && drm_dp_read_sink_count(dp->aux) <= 0; i++)
			msleep(50);
"""+s[j:]
b="	drm_edid_connector_update(connector, drm_edid);\n\n"
i=s.index(b)+len(b); j=s.index("	if (!drm_edid) {\n		DRM_ERROR")
s=s[:i]+s[j:]
assert "sb4dbg" not in s
open(p,"w").write(s)
