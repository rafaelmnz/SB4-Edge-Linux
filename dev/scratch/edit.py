import sys
p = sys.argv[1]
s = open(p).read()
assert "inject_store" not in s
s = s.replace("""	u8 hpd_irq;
	u8 mux_ctrl;
};""", """	u8 hpd_irq;
	u8 mux_ctrl;
	/* sb4edge: state set from userspace, not by the ADSP: no PAN_ACK */
	bool injected;
};""", 1)
s = s.replace("""	pmic_glink_altmode_request(altmode, ALTMODE_PAN_ACK, alt_port->index);
}
""", """	if (alt_port->injected)
		alt_port->injected = false;
	else
		pmic_glink_altmode_request(altmode, ALTMODE_PAN_ACK, alt_port->index);
}
""", 1)
s = s.replace("""static void pmic_glink_altmode_callback(""", r'''/*
 * sb4edge: on the Samsung Galaxy Book4 Edge the USB-C ports have Samsung S2MM006 PD controllers that talk to
 * Windows' EmuEC.sys, not to the ADSP, so no USBC_NOTIFY_IND ever arrives. The usbc helper reads the alt mode
 * state from the controllers and hands it in here, so the mux, retimer and DP HPD bridge follow it:
 *
 *   echo "<port> <normal|reverse|none> safe" > inject
 *   echo "<port> <normal|reverse|none> usb" > inject
 *   echo "<port> <normal|reverse|none> dp <A-F> <hpd 0|1> <irq 0|1>" > inject
 */
static ssize_t inject_store(struct device *dev, struct device_attribute *attr,
			    const char *buf, size_t count)
{
	struct pmic_glink_altmode *altmode = dev_get_drvdata(dev);
	struct pmic_glink_altmode_port *alt_port;
	char orient[8], state[8], pin = 0;
	unsigned int port, hpd = 0, irq = 0;
	int n;

	n = sscanf(buf, "%u %7s %7s %c %u %u", &port, orient, state, &pin, &hpd, &irq);
	if (n < 3 || port >= ARRAY_SIZE(altmode->ports) || !altmode->ports[port].altmode)
		return -EINVAL;
	alt_port = &altmode->ports[port];

	flush_work(&alt_port->work);
	if (!strcmp(orient, "normal"))
		alt_port->orientation = TYPEC_ORIENTATION_NORMAL;
	else if (!strcmp(orient, "reverse"))
		alt_port->orientation = TYPEC_ORIENTATION_REVERSE;
	else if (!strcmp(orient, "none"))
		alt_port->orientation = TYPEC_ORIENTATION_NONE;
	else
		return -EINVAL;

	if (!strcmp(state, "dp")) {
		if (n < 6 || pin < 'A' || pin > 'F')
			return -EINVAL;
		alt_port->svid = USB_TYPEC_DP_SID;
		alt_port->mux_ctrl = (pin == 'D' || pin == 'F') ? MUX_CTRL_STATE_USB3_DP :
				     MUX_CTRL_STATE_DP4LN;
		alt_port->mode = pin - 'A';
		alt_port->hpd_state = !!hpd;
		alt_port->hpd_irq = !!irq;
	} else if (!strcmp(state, "usb")) {
		alt_port->svid = 0;
		alt_port->mux_ctrl = MUX_CTRL_STATE_USB3_ONLY;
	} else if (!strcmp(state, "safe")) {
		/* a DP partner that went away still needs its HPD dropped */
		if (alt_port->svid == USB_TYPEC_DP_SID)
			alt_port->hpd_state = 0;
		alt_port->mux_ctrl = MUX_CTRL_STATE_NO_CONN;
	} else {
		return -EINVAL;
	}
	alt_port->injected = true;
	queue_work(system_freezable_wq, &alt_port->work);
	flush_work(&alt_port->work);
	if (!strcmp(state, "safe"))
		alt_port->svid = 0;
	return count;
}
static DEVICE_ATTR_WO(inject);

static void pmic_glink_altmode_remove_inject(void *data)
{
	device_remove_file(data, &dev_attr_inject);
}

static void pmic_glink_altmode_callback(''', 1)
s = s.replace("""	altmode->client = devm_pmic_glink_client_alloc(dev,""", """	dev_set_drvdata(dev, altmode);
	ret = device_create_file(dev, &dev_attr_inject);
	if (ret)
		return ret;
	ret = devm_add_action_or_reset(dev, pmic_glink_altmode_remove_inject, dev);
	if (ret)
		return ret;

	altmode->client = devm_pmic_glink_client_alloc(dev,""", 1)
assert s.count("inject") > 10
open(p, "w").write(s)
