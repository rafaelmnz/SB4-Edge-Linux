import sys
p=sys.argv[1]; s=open(p).read()
a="""		pr_info("sb4dbg: edid raw i2c ret %d: %*ph, sink count %d, link connected %u\\n", t, 8, hdr,
			drm_dp_read_sink_count(dp->aux), msm_dp_aux_is_link_connected(dp->aux));
"""
assert s.count(a)==1
s=s.replace(a,a+"""		{
			static u8 blk[128];
			unsigned int k, b;

			for (b = 0; b < 2; b++) {
				u8 o = b * 128, sum = 0;
				struct i2c_msg n[2] = {
					{ .addr = 0x50, .flags = 0, .len = 1, .buf = &o },
					{ .addr = 0x50, .flags = I2C_M_RD, .len = 128, .buf = blk },
				};

				memset(blk, 0, sizeof(blk));
				t = i2c_transfer(&dp->aux->ddc, n, 2);
				for (k = 0; k < 128; k++)
					sum += blk[k];
				pr_info("sb4dbg: block %u ret %d sum %02x: %*ph ... %*ph\\n", b, t, sum,
					16, blk, 16, blk + 112);
			}
			for (k = 0; k < 4; k++) {
				const struct drm_edid *e = drm_edid_read_ddc(connector, &dp->aux->ddc);

				pr_info("sb4dbg: drm_edid_read_ddc retry %u: %s\\n", k, e ? "ok" : "NULL");
				if (e) {
					drm_edid = e;
					drm_edid_connector_update(connector, drm_edid);
					break;
				}
				msleep(200);
			}
		}
""")
open(p,"w").write(s)
