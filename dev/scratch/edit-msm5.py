import sys
p=sys.argv[1]; s=open(p).read()
a="""	struct mutex plugged_lock;
	bool plugged;
"""
assert s.count(a)==1
s=s.replace(a,a+"""	/*
	 * sb4edge: the last HPD notification (USB-C HPD bridge) said disconnected. Detect then trusts it:
	 * the PS8830 retimer, still in DP mode, keeps answering AUX for an adapter that is gone.
	 */
	bool hpd_low;
""")
b="""	guard(mutex)(&priv->plugged_lock);
	ret = pm_runtime_resume_and_get(&dp->pdev->dev);
	if (ret) {
		DRM_ERROR("failed to pm_runtime_resume\\n");
		return status;
	}
"""
assert s.count(b)==1
s=s.replace(b,"""	guard(mutex)(&priv->plugged_lock);
	if (priv->hpd_low && !dp->is_edp)
		return status;
	ret = pm_runtime_resume_and_get(&dp->pdev->dev);
	if (ret) {
		DRM_ERROR("failed to pm_runtime_resume\\n");
		return status;
	}
""")
c="""	hpd_link_status = msm_dp_aux_is_link_connected(dp->aux);
"""
assert s.count(c)==1
s=s.replace(c,c+"""	WRITE_ONCE(dp->hpd_low, status != connector_status_connected);
""")
open(p,"w").write(s)
