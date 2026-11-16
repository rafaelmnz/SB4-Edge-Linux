// SPDX-License-Identifier: GPL-2.0
/*
 * Samsung Galaxy Book4 Edge battery driver.
 *
 * Reads battery state from the Samsung ENE KB9058 EC via its Mbox
 * protocol on I2C. The Qualcomm DSDT on this laptop exposes the same
 * data through an ACPI OperationRegion of type 0xA1, but there is no
 * in-kernel handler for that region type, so the qcom-battmgr power
 * supply comes up empty. This driver bypasses ACPI entirely and talks
 * to the EC directly.
 *
 * EC register layout (from DSDT _SB.ECTC ECR region):
 *   0x80 bit0 = B1EX   (battery 1 present)
 *   0x80 bit2 = ACEX   (AC adapter online)
 *   0x84      = B1ST   (state: bit0 discharge, bit1 charge, bit3 full)
 *   0xA0..A3  = B1RR   (remaining capacity; upper word big-endian = mAh)
 *   0xA4..A7  = B1PV   (upper word BE = voltage mV, lower BE = signed mA)
 *   0xB0..B3  = B1AF   (upper BE = design mAh, lower BE = full-charge mAh)
 *   0xB4..B7  = B1VL   (lower BE = nominal design voltage mV)
 *
 * Charge limit (sb4edge, from Windows EmuEC.sys 7.22.18.735 and EC2.sys 15.27.1.994):
 * Samsung Settings' "Battery protection" / Battery Life Extender is EmuEC IOCTL 0x58430198
 * (get 0x58430194), which becomes EC mailbox command 0xE9 (2 bytes in, 3 out):
 *   in { 0x90, percent }  set the limit (0 = off)
 *   in { 0x91, 0 }        get; out[0] = percent
 * EC2's mailbox sequence: claim a bit in the slot byte 0xF49F (mirrored in 0xF49E), wait for
 * 0xFF10 to read 0, write the input to 0xF480.., the command to 0xFF10, wait for 0xFF10 = 0,
 * read the output from 0xF480.., then free the slot; retry if 0xF49E flags the slot dirty.
 * Same command and sub-commands as the x86 samsung-galaxybook driver. Exposed as
 * charge_control_end_threshold (100 = off) for UPower / GNOME "Preserve battery health".
 *
 * Author: Galaxy Book4 Edge Linux research (reverse engineered from EC2.sys)
 */

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>

#define DRV_NAME		"samsung_galaxybook_battery"
#define POLL_INTERVAL_S		5

/* Mbox framing */
#define MBOX_WRITE_PREFIX	0x40
#define MBOX_READ_PREFIX	0x30
#define MBOX_READ_SUCCESS	0x50

#define CMD_TARGET_HI		0xF4
#define CMD_TARGET_LO		0x80
#define CMD_EXEC_HI		0xFF
#define CMD_EXEC_LO		0x10
#define EXEC_READ		0x88

/* Mailbox commands (EC2.sys SecEne9058KbcSendExCmdFull) */
#define EC_MBOX_DATA		0xF480
#define EC_MBOX_CMD		0xFF10
#define EC_SLOT_DIRTY		0xF49E
#define EC_SLOT_OWNED		0xF49F
#define EC_CMD_BATT_LIMIT	0xE9
#define BATT_LIMIT_SET		0x90
#define BATT_LIMIT_GET		0x91

/* EC registers we care about */
#define EC_REG_FLAGS		0x80	/* B1EX + ACEX */
#define EC_REG_B1ST		0x84	/* state */
#define EC_REG_B1RR		0xA0	/* remaining mAh (BE upper word) */
#define EC_REG_B1PV		0xA4	/* voltage mV + signed current mA */
#define EC_REG_B1AF		0xB0	/* design mAh + full-charge mAh */
#define EC_REG_B1VL		0xB4	/* design voltage mV */

#define B1ST_DISCHARGE		BIT(0)
#define B1ST_CHARGE		BIT(1)
#define B1ST_LIMIT		BIT(3)	/* ACPI _BST: charge limiting */

#define FLAG_B1EX		BIT(0)
#define FLAG_ACEX		BIT(2)

struct sgb_bat {
	struct i2c_client	*client;
	struct power_supply	*psy;
	struct delayed_work	poll;
	struct mutex		lock;		/* serialises EC access */

	/* cached readings (µV / µA / µAh, per power_supply class convention) */
	int	voltage_now;
	int	voltage_design;
	int	current_now;
	int	charge_now;
	int	charge_full;
	int	charge_full_design;
	int	status;
	bool	present;
	bool	ac_online;
	bool	have_data;
};

/* ------------------------------------------------------------------ */
/* Mbox primitives, built on raw i2c_transfer() so we don't need the   */
/* i2c-dev character device.                                           */
/* ------------------------------------------------------------------ */

static int sgb_mbox_write(struct i2c_client *c, u8 hi, u8 lo, u8 data)
{
	u8 buf[5] = { MBOX_WRITE_PREFIX, 0x00, hi, lo, data };
	struct i2c_msg msg = {
		.addr  = c->addr,
		.flags = 0,
		.len   = sizeof(buf),
		.buf   = buf,
	};
	int ret = i2c_transfer(c->adapter, &msg, 1);

	if (ret != 1)
		return ret < 0 ? ret : -EIO;
	usleep_range(5000, 6000);
	return 0;
}

static int sgb_mbox_read(struct i2c_client *c, u8 hi, u8 lo, u8 *out)
{
	u8 wbuf[4] = { MBOX_READ_PREFIX, 0x00, hi, lo };
	u8 rbuf[2] = { 0, 0 };
	struct i2c_msg msgs[2] = {
		{ .addr = c->addr, .flags = 0,        .len = 4, .buf = wbuf },
		{ .addr = c->addr, .flags = I2C_M_RD, .len = 2, .buf = rbuf },
	};
	int ret = i2c_transfer(c->adapter, msgs, 2);

	if (ret != 2)
		return ret < 0 ? ret : -EIO;
	if (rbuf[0] != MBOX_READ_SUCCESS)
		return -EIO;
	*out = rbuf[1];
	return 0;
}

static int sgb_ec_read_byte(struct i2c_client *c, u8 reg, u8 *out)
{
	int ret;

	ret = sgb_mbox_write(c, CMD_TARGET_HI, CMD_TARGET_LO, reg);
	if (ret)
		return ret;
	ret = sgb_mbox_write(c, CMD_EXEC_HI, CMD_EXEC_LO, EXEC_READ);
	if (ret)
		return ret;
	return sgb_mbox_read(c, CMD_TARGET_HI, CMD_TARGET_LO, out);
}

static int sgb_ec_read_block(struct i2c_client *c, u8 reg, u8 *buf, int n)
{
	int i, ret;

	for (i = 0; i < n; i++) {
		ret = sgb_ec_read_byte(c, reg + i, &buf[i]);
		if (ret)
			return ret;
	}
	return 0;
}

static int sgb_ram_write(struct i2c_client *c, u16 addr, u8 data)
{
	return sgb_mbox_write(c, addr >> 8, addr & 0xff, data);
}

static int sgb_ram_read(struct i2c_client *c, u16 addr, u8 *out)
{
	return sgb_mbox_read(c, addr >> 8, addr & 0xff, out);
}

/* SecEcIsMboxIlde: up to 31 polls of the command byte, 1 ms apart */
static int sgb_mbox_wait_idle(struct i2c_client *c)
{
	u8 v;
	int i, ret;

	for (i = 0; i <= 30; i++) {
		ret = sgb_ram_read(c, EC_MBOX_CMD, &v);
		if (ret)
			return ret;
		if (!v)
			return 0;
		usleep_range(1000, 2000);
	}
	return -ETIMEDOUT;
}

/* GetSlotIdx: take the lowest free bit of the slot byte */
static int sgb_slot_get(struct i2c_client *c, u8 *mask)
{
	u8 own, dirty, m = 1;
	int ret;

	ret = sgb_ram_read(c, EC_SLOT_OWNED, &own);
	if (!ret)
		ret = sgb_ram_read(c, EC_SLOT_DIRTY, &dirty);
	if (ret)
		return ret;
	if (own == 0xff)
		return -EBUSY;
	if (own != dirty) {
		ret = sgb_ram_write(c, EC_SLOT_DIRTY, own);
		if (ret)
			return ret;
	}
	while (own & m)
		m <<= 1;
	*mask = m;
	return sgb_ram_write(c, EC_SLOT_OWNED, own | m);
}

/* ClearSlotIdx */
static int sgb_slot_put(struct i2c_client *c, u8 mask)
{
	u8 own, dirty;
	int ret;

	ret = sgb_ram_read(c, EC_SLOT_OWNED, &own);
	if (!ret)
		ret = sgb_ram_read(c, EC_SLOT_DIRTY, &dirty);
	if (!ret)
		ret = sgb_ram_write(c, EC_SLOT_OWNED, own & ~mask);
	if (!ret)
		ret = sgb_ram_write(c, EC_SLOT_DIRTY, dirty & ~mask);
	return ret;
}

/* SecEne9058KbcSendExCmdFull, for commands >= 0x80. Caller holds b->lock. */
static int sgb_ec_cmd(struct i2c_client *c, u8 cmd, const u8 *in, int nin, u8 *out, int nout)
{
	u8 mask, dirty;
	int i, try, ret;

	ret = sgb_mbox_wait_idle(c);
	if (ret)
		return ret;

	for (try = 0; try < 3; try++) {
		ret = sgb_slot_get(c, &mask);
		if (ret)
			return ret;
		for (i = 0; i < nin && !ret; i++)
			ret = sgb_ram_write(c, EC_MBOX_DATA + i, in[i]);
		if (!ret)
			ret = sgb_ram_write(c, EC_MBOX_CMD, cmd);
		if (!ret)
			ret = sgb_mbox_wait_idle(c);
		for (i = 0; i < nout && !ret; i++)
			ret = sgb_ram_read(c, EC_MBOX_DATA + i, &out[i]);
		if (!ret)
			ret = sgb_ram_read(c, EC_SLOT_DIRTY, &dirty);
		sgb_slot_put(c, mask);
		if (ret)
			return ret;
		if (!(dirty & mask))
			return 0;
		/* someone else used the mailbox meanwhile: run it again */
		ret = sgb_mbox_wait_idle(c);
		if (ret)
			return ret;
	}
	return -EIO;
}

/*
 * The keyboard-light module (samsung_galaxybook_kbd) uses the same mailbox: Samsung.Firmware's
 * SetKbdBacklit/GetKbdBacklit are mailbox commands 0xFD (1 byte in) and 0xFC (1 byte out). Exported
 * here so both drivers share one lock and one slot protocol.
 */
static DEFINE_MUTEX(sgb_ec_lock);
static struct sgb_bat *sgb_ec;

int sgb_ec_excmd(u8 cmd, const u8 *in, int nin, u8 *out, int nout);

int sgb_ec_excmd(u8 cmd, const u8 *in, int nin, u8 *out, int nout)
{
	int ret = -EPROBE_DEFER;

	mutex_lock(&sgb_ec_lock);
	if (sgb_ec) {
		mutex_lock(&sgb_ec->lock);
		ret = sgb_ec_cmd(sgb_ec->client, cmd, in, nin, out, nout);
		mutex_unlock(&sgb_ec->lock);
	}
	mutex_unlock(&sgb_ec_lock);
	return ret;
}
EXPORT_SYMBOL_GPL(sgb_ec_excmd);

static int sgb_get_limit(struct sgb_bat *b, int *pct)
{
	u8 in[2] = { BATT_LIMIT_GET, 0 }, out[3];
	int ret = sgb_ec_cmd(b->client, EC_CMD_BATT_LIMIT, in, 2, out, 3);

	if (ret)
		return ret;
	*pct = out[0] && out[0] < 100 ? out[0] : 100;	/* 0 = no limit */
	return 0;
}

static int sgb_set_limit(struct sgb_bat *b, int pct)
{
	u8 in[2] = { BATT_LIMIT_SET, pct >= 100 ? 0 : pct }, out[3];

	if (pct < 1 || pct > 100)
		return -EINVAL;
	return sgb_ec_cmd(b->client, EC_CMD_BATT_LIMIT, in, 2, out, 3);
}

/* ------------------------------------------------------------------ */
/* Poll work: read EC regs and update cached values                     */
/* ------------------------------------------------------------------ */

static void sgb_poll_work(struct work_struct *w)
{
	struct sgb_bat *b = container_of(to_delayed_work(w), struct sgb_bat, poll);
	u8 flags, b1st, rr[4], pv[4], af[4], vl[4];
	u16 remaining, voltage, design_c, fullchg_c, design_v;
	s16 current_ma;
	int ret;

	mutex_lock(&b->lock);

	ret = sgb_ec_read_byte(b->client, EC_REG_FLAGS, &flags);
	if (ret)
		goto err;
	ret = sgb_ec_read_byte(b->client, EC_REG_B1ST, &b1st);
	if (ret)
		goto err;
	ret = sgb_ec_read_block(b->client, EC_REG_B1RR, rr, 4);
	if (ret)
		goto err;
	ret = sgb_ec_read_block(b->client, EC_REG_B1PV, pv, 4);
	if (ret)
		goto err;
	ret = sgb_ec_read_block(b->client, EC_REG_B1AF, af, 4);
	if (ret)
		goto err;
	ret = sgb_ec_read_block(b->client, EC_REG_B1VL, vl, 4);
	if (ret)
		goto err;

	/*
	 * DSDT _BST does `ByteSwap16(B1RR >> 16)` — that's the big-endian
	 * word at offsets [2][3] of the 4-byte LE field. Likewise the lower
	 * word BE sits at offsets [0][1].
	 */
	remaining  = ((u16)rr[2] << 8) | rr[3];		/* mAh */
	voltage    = ((u16)pv[2] << 8) | pv[3];		/* mV */
	current_ma = (s16)(((u16)pv[0] << 8) | pv[1]);	/* signed mA */
	/*
	 * sb4edge: on the Galaxy Book4 Edge 16 the words are the other way round: checked against the
	 * smart battery itself (SBS DesignCapacity 3900 mAh, FullChargeCapacity 3202 mAh), so the
	 * upper word is the full-charge capacity and the lower word the design capacity.
	 */
	fullchg_c  = ((u16)af[2] << 8) | af[3];		/* mAh */
	design_c   = ((u16)af[0] << 8) | af[1];		/* mAh */
	design_v   = ((u16)vl[0] << 8) | vl[1];		/* mV */

	/* 0xFFFF == "unknown / uninitialised" per DSDT convention */
	if (remaining == 0xFFFF)
		remaining = 0;
	if (design_c == 0xFFFF)
		design_c = 0;
	if (fullchg_c == 0xFFFF)
		fullchg_c = 0;

	b->present            = !!(flags & FLAG_B1EX);
	b->ac_online          = !!(flags & FLAG_ACEX);
	b->voltage_now        = (int)voltage   * 1000;		/* mV -> µV */
	b->voltage_design     = (int)design_v  * 1000;
	b->current_now        = (int)current_ma * 1000;		/* mA -> µA */
	b->charge_now         = (int)remaining * 1000;		/* mAh -> µAh */
	b->charge_full        = (int)(fullchg_c ? fullchg_c : design_c) * 1000;
	b->charge_full_design = (int)design_c  * 1000;

	/*
	 * sb4edge: bit 3 is the ACPI _BST "charge limiting" bit, not "full". The EC sets it whenever the
	 * charge limit (Preserve battery health) is on, even while discharging at 24 %, so the real
	 * direction bits win and bit 3 alone means "plugged in, held at the limit".
	 */
	if (b1st & B1ST_DISCHARGE)
		b->status = POWER_SUPPLY_STATUS_DISCHARGING;
	else if (b1st & B1ST_CHARGE)
		b->status = POWER_SUPPLY_STATUS_CHARGING;
	else if (b1st & B1ST_LIMIT)
		b->status = b->ac_online ? POWER_SUPPLY_STATUS_NOT_CHARGING :
					   POWER_SUPPLY_STATUS_DISCHARGING;
	else if (b->ac_online && fullchg_c &&
		 remaining >= (fullchg_c * 95 / 100))
		b->status = POWER_SUPPLY_STATUS_FULL;
	else if (b->ac_online)
		b->status = POWER_SUPPLY_STATUS_NOT_CHARGING;
	else
		b->status = POWER_SUPPLY_STATUS_DISCHARGING;

	b->have_data = true;
	mutex_unlock(&b->lock);
	power_supply_changed(b->psy);
	goto resched;

err:
	mutex_unlock(&b->lock);
	dev_warn_ratelimited(&b->client->dev,
			     "EC read failed: %d\n", ret);
resched:
	schedule_delayed_work(&b->poll, POLL_INTERVAL_S * HZ);
}

/* ------------------------------------------------------------------ */
/* power_supply properties                                              */
/* ------------------------------------------------------------------ */

static enum power_supply_property sgb_props[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN,
	POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_CHARGE_NOW,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_MANUFACTURER,
	POWER_SUPPLY_PROP_SCOPE,
	POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD,
};

static int sgb_get_prop(struct power_supply *psy,
			enum power_supply_property prop,
			union power_supply_propval *val)
{
	struct sgb_bat *b = power_supply_get_drvdata(psy);
	int ret = 0;

	mutex_lock(&b->lock);

	if (prop == POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD) {
		ret = sgb_get_limit(b, &val->intval);
		mutex_unlock(&b->lock);
		return ret;
	}

	if (!b->have_data &&
	    prop != POWER_SUPPLY_PROP_MODEL_NAME &&
	    prop != POWER_SUPPLY_PROP_MANUFACTURER &&
	    prop != POWER_SUPPLY_PROP_TECHNOLOGY &&
	    prop != POWER_SUPPLY_PROP_SCOPE) {
		mutex_unlock(&b->lock);
		return -ENODATA;
	}

	switch (prop) {
	case POWER_SUPPLY_PROP_STATUS:
		val->intval = b->status;
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = b->present;
		break;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		val->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		val->intval = b->voltage_now;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN:
		val->intval = b->voltage_design;
		break;
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		val->intval = b->current_now;
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		val->intval = b->charge_now;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		val->intval = b->charge_full;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		val->intval = b->charge_full_design;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		if (b->charge_full > 0)
			val->intval = clamp_t(int,
				(int)((long long)b->charge_now * 100 /
				      b->charge_full),
				0, 100);
		else
			ret = -ENODATA;
		break;
	case POWER_SUPPLY_PROP_MODEL_NAME:
		val->strval = "Galaxy Book4 Edge Battery";
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		val->strval = "Samsung";
		break;
	case POWER_SUPPLY_PROP_SCOPE:
		val->intval = POWER_SUPPLY_SCOPE_SYSTEM;
		break;
	default:
		ret = -EINVAL;
	}

	mutex_unlock(&b->lock);
	return ret;
}

static int sgb_set_prop(struct power_supply *psy, enum power_supply_property prop,
			const union power_supply_propval *val)
{
	struct sgb_bat *b = power_supply_get_drvdata(psy);
	int ret;

	if (prop != POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD)
		return -EINVAL;
	mutex_lock(&b->lock);
	ret = sgb_set_limit(b, val->intval);
	mutex_unlock(&b->lock);
	return ret;
}

static int sgb_prop_writeable(struct power_supply *psy, enum power_supply_property prop)
{
	return prop == POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD;
}

static const struct power_supply_desc sgb_psy_desc = {
	.name		= "samsung-galaxybook-bat",
	.type		= POWER_SUPPLY_TYPE_BATTERY,
	.properties	= sgb_props,
	.num_properties	= ARRAY_SIZE(sgb_props),
	.get_property	= sgb_get_prop,
	.set_property	= sgb_set_prop,
	.property_is_writeable = sgb_prop_writeable,
};

/* ------------------------------------------------------------------ */
/* i2c probe / remove                                                   */
/* ------------------------------------------------------------------ */

static int sgb_probe(struct i2c_client *client)
{
	struct sgb_bat *b;
	struct power_supply_config cfg = { 0 };
	u8 probe_byte;
	int ret;

	b = devm_kzalloc(&client->dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;

	b->client = client;
	mutex_init(&b->lock);
	INIT_DELAYED_WORK(&b->poll, sgb_poll_work);

	/* Probe the EC with a single-byte read to validate we're talking
	 * to the right thing before registering the power supply. */
	ret = sgb_ec_read_byte(client, EC_REG_FLAGS, &probe_byte);
	if (ret) {
		dev_err(&client->dev,
			"EC probe read failed (%d) — wrong bus/addr?\n", ret);
		return ret;
	}
	dev_info(&client->dev,
		 "EC flags byte = 0x%02x (B1EX=%d, ACEX=%d)\n",
		 probe_byte,
		 !!(probe_byte & FLAG_B1EX),
		 !!(probe_byte & FLAG_ACEX));

	{
		int pct;

		ret = sgb_get_limit(b, &pct);
		if (ret)
			dev_warn(&client->dev, "charge limit query failed (%d)\n", ret);
		else
			dev_info(&client->dev, "charge limit %d%%%s\n", pct,
				 pct == 100 ? " (off)" : "");
	}

	cfg.drv_data = b;
	cfg.fwnode   = dev_fwnode(&client->dev);

	b->psy = devm_power_supply_register(&client->dev,
					    &sgb_psy_desc, &cfg);
	if (IS_ERR(b->psy)) {
		ret = PTR_ERR(b->psy);
		dev_err(&client->dev,
			"power_supply_register failed: %d\n", ret);
		return ret;
	}

	i2c_set_clientdata(client, b);
	mutex_lock(&sgb_ec_lock);
	sgb_ec = b;
	mutex_unlock(&sgb_ec_lock);
	schedule_delayed_work(&b->poll, 0);		/* immediate first read */
	dev_info(&client->dev,
		 "Samsung Galaxy Book4 Edge battery driver ready\n");
	return 0;
}

static void sgb_remove(struct i2c_client *client)
{
	struct sgb_bat *b = i2c_get_clientdata(client);

	mutex_lock(&sgb_ec_lock);
	sgb_ec = NULL;
	mutex_unlock(&sgb_ec_lock);
	cancel_delayed_work_sync(&b->poll);
}

/* i2c_device_id.name is limited to 20 chars, so use a shorter id.
 * The user-facing power_supply name is still "samsung-galaxybook-bat". */
static const struct i2c_device_id sgb_id[] = {
	{ "sgbook-battery", 0 },
	{ }
};
MODULE_DEVICE_TABLE(i2c, sgb_id);

static const struct of_device_id sgb_of_match[] = {
	{ .compatible = "samsung,galaxybook-battery" },
	{ }
};
MODULE_DEVICE_TABLE(of, sgb_of_match);

static struct i2c_driver sgb_driver = {
	.driver = {
		.name		= DRV_NAME,
		.of_match_table	= sgb_of_match,
	},
	.probe		= sgb_probe,
	.remove		= sgb_remove,
	.id_table	= sgb_id,
};
module_i2c_driver(sgb_driver);

MODULE_AUTHOR("Galaxy Book4 Edge Linux research");
MODULE_DESCRIPTION("Samsung Galaxy Book4 Edge battery driver (EC Mbox)");
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("i2c:sgbook-battery");
