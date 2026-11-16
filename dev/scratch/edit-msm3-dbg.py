import sys
p=sys.argv[1]; s=open(p).read()
a="""	for (i = 0; i < 3; i++)
		if (i2c_transfer(ddc, &m[3 - n], n) == n)
			return 0;
	return -EIO;"""
assert s.count(a)==1
s=s.replace(a,"""	for (i = 0; i < 3; i++) {
		int r = i2c_transfer(ddc, &m[3 - n], n);

		pr_info("sb4dbg: block %u try %d ret %d len %zu first %*ph\\n", block, i, r, len, 8, buf);
		if (r == n)
			return 0;
	}
	return -EIO;""")
b="""		drm_edid = drm_edid_read_custom(connector, msm_dp_read_edid_block, &dp->aux->ddc);
"""
assert s.count(b)==1
s=s.replace(b,"""		pr_info("sb4dbg: probe_ddc %d force %d\\n", drm_probe_ddc(&dp->aux->ddc), connector->force);
		drm_edid = drm_edid_read_custom(connector, msm_dp_read_edid_block, &dp->aux->ddc);
		for (int k = 0; !drm_edid && k < 10; k++) {
			msleep(100);
			drm_edid = drm_edid_read_custom(connector, msm_dp_read_edid_block, &dp->aux->ddc);
			pr_info("sb4dbg: custom retry %d: %s\\n", k, drm_edid ? "ok" : "NULL");
		}
""")
open(p,"w").write(s)
