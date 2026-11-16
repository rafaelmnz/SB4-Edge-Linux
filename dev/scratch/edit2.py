import sys
p=sys.argv[1]; s=open(p).read()
a="""	if (!strcmp(state, "dp")) {
		if (n < 6 || pin < 'A' || pin > 'F')
			return -EINVAL;
"""
assert s.count(a)==1
s=s.replace(a,"""	if (!strcmp(state, "dp")) {
		u8 mux;

		if (n < 6 || pin < 'A' || pin > 'F')
			return -EINVAL;
		mux = (pin == 'D' || pin == 'F') ? MUX_CTRL_STATE_USB3_DP : MUX_CTRL_STATE_DP4LN;
		/*
		 * Lanes already in this DP mode: only pass the HPD change on. Setting the mux and retimer
		 * again resets the AUX path for a moment, and msm reads the sink count and EDID right
		 * after the HPD notification.
		 */
		if (alt_port->svid == USB_TYPEC_DP_SID && alt_port->mux_ctrl == mux &&
		    alt_port->mode == pin - 'A' && alt_port->orientation == orientation) {
			alt_port->hpd_state = !!hpd;
			alt_port->hpd_irq = !!irq;
			drm_aux_hpd_bridge_notify(&alt_port->bridge->dev, hpd ? connector_status_connected :
						  connector_status_disconnected);
			return count;
		}
""",1)
# need orientation parsed into a local before comparing; restructure orientation parsing
b="""	flush_work(&alt_port->work);
	if (!strcmp(orient, "normal"))
		alt_port->orientation = TYPEC_ORIENTATION_NORMAL;
	else if (!strcmp(orient, "reverse"))
		alt_port->orientation = TYPEC_ORIENTATION_REVERSE;
	else if (!strcmp(orient, "none"))
		alt_port->orientation = TYPEC_ORIENTATION_NONE;
	else
		return -EINVAL;
"""
assert s.count(b)==1
s=s.replace(b,"""	flush_work(&alt_port->work);
	if (!strcmp(orient, "normal"))
		orientation = TYPEC_ORIENTATION_NORMAL;
	else if (!strcmp(orient, "reverse"))
		orientation = TYPEC_ORIENTATION_REVERSE;
	else if (!strcmp(orient, "none"))
		orientation = TYPEC_ORIENTATION_NONE;
	else
		return -EINVAL;
""",1)
c="""		alt_port->svid = USB_TYPEC_DP_SID;
		alt_port->mux_ctrl = (pin == 'D' || pin == 'F') ? MUX_CTRL_STATE_USB3_DP :
				     MUX_CTRL_STATE_DP4LN;"""
assert s.count(c)==1
s=s.replace(c,"""		alt_port->svid = USB_TYPEC_DP_SID;
		alt_port->mux_ctrl = mux;""",1)
d="""	alt_port->injected = true;
	queue_work(system_freezable_wq, &alt_port->work);"""
assert s.count(d)==1
s=s.replace(d,"""	alt_port->orientation = orientation;
	alt_port->injected = true;
	queue_work(system_freezable_wq, &alt_port->work);""",1)
e="""	unsigned int port, hpd = 0, irq = 0;
	int n;
"""
assert s.count(e)==1
s=s.replace(e,"""	unsigned int port, hpd = 0, irq = 0;
	enum typec_orientation orientation;
	int n;
""",1)
open(p,"w").write(s)
