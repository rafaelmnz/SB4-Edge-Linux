// SPDX-License-Identifier: GPL-2.0
/*
 * Keyboard backlight of the Samsung Galaxy Book4 Edge (X1E80100/X1E84100), set the way Windows does it:
 * Samsung.Firmware.dll's SetKbdBacklit/GetKbdBacklit are ENE KB9058 mailbox commands (EC2.sys
 * SecEne9058KbcSendExCmdFull, on the EC's 0x64 port):
 *   0xFD, in { level }    level 0 off, 1 low, 2 mid, 3 high
 *   0xFC, out { level }
 * The EC holds every level steadily after one command, with no refresh. The mailbox is shared with the
 * battery driver, which owns that I2C device, so this calls its exported sgb_ec_excmd().
 *
 * The other EC port (0x62 on the GENI I2C at 0xb94000) also has a backlight command, { 0x10, timeout, level }
 * (OpenBSD samsabi(4), EC2.sys IOCTL_SET_KBDBLT), but there the EC fades the light out within a second:
 * OpenBSD resends it every second, which only holds level 3 (levels 1 and 2 flicker). Not used.
 * Exposed as "samsung-galaxybook::kbd_backlight" for UPower/GNOME.
 *
 * The same port sets the fan (EC2.sys IOCTL_SET_FANRPM2, decoded by omarchy's gb4e work):
 *   write { 0x17, rpm as big-endian u32 }   0 stops the fan; the EC keeps the target until the next write
 * The EC never starts the fan by itself, so the fan curve lives in userspace (sb4edge-fan); this exposes
 * it as hwmon fan1_target and sends the target again on resume.
 *
 * Performance mode (Samsung Settings' Quiet / Optimized / Performance) is a platform_profile. Samsung's
 * service sends a SABI call that the DSDT (\_SB.SCAI PRF3) turns into new thermal-zone trip points for
 * Windows and one mailbox command to the EC:
 *   0xEE, in { 0x80, mode }   mode 0x0A quiet ("SILENT"), 0x00 optimized ("AUTO"), 0x15 performance ("MAXPERF")
 * The trip points have no Linux counterpart (the DT thermal zones apply); sb4edge-fan reads the profile
 * and sets its fan curve and a CPU frequency cap to match.
 *
 * Fn+F9 (the keyboard-light key) is not a key: the HID keyboard (i2c-hid 0CF2:9050) sends vendor
 * report 7 (usage page 0xFF00) with the bytes "ene", 0, 0xBF on each press and no release. hid-generic
 * maps nothing for that page, so this module also binds a HID driver to the keyboard that passes
 * everything on unchanged (with hid-generic's INPUT_PER_APP quirk) and catches that report to cycle the light (0-1-2-3-0, or off/on with
 * levels=0), reporting the change through brightness_hw_changed so GNOME shows its OSD.
 */
#include <linux/hid.h>
#include <linux/hwmon.h>
#include <linux/i2c.h>
#include <linux/string.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_profile.h>
#include <linux/workqueue.h>

#define EC_KBD_SET	0xfd	/* mailbox commands */
#define EC_KBD_GET	0xfc
#define KBD_MAX		3
#define FAN_SET		0x17
#define FAN_MAX		9000	/* the fan is no faster above this */
#define EC_PERF_MODE	0xee	/* mailbox command, in { 0x80, mode } */
#define PERF_QUIET	0x0a
#define PERF_AUTO	0x00
#define PERF_MAX	0x15

#define HOTKEY_REPORT	0x07	/* vendor report of the keyboard */
#define HOTKEY_KBD	0xbf	/* Fn+F9 */

static bool levels = true;
module_param(levels, bool, 0444);
MODULE_PARM_DESC(levels, "Expose levels 1-3 (default); 0 makes the light on/off");

struct sgb_kbd {
	struct i2c_client *client;
	struct led_classdev led;
	struct mutex lock;
	u8 level;			/* EC level 0..3 */
	u32 fan_rpm;			/* last fan target sent */
	enum platform_profile_option profile;
};

int sgb_ec_excmd(u8 cmd, const u8 *in, int nin, u8 *out, int nout);	/* samsung_galaxybook_battery */

static int sgb_kbd_send(struct sgb_kbd *k, u8 level)
{
	return sgb_ec_excmd(EC_KBD_SET, &level, 1, NULL, 0);
}

static int sgb_kbd_get(struct sgb_kbd *k)
{
	u8 level;
	int ret = sgb_ec_excmd(EC_KBD_GET, NULL, 0, &level, 1);

	if (ret)
		return ret;
	return level <= KBD_MAX ? level : -EPROTO;
}

static int sgb_fan_send(struct sgb_kbd *k, u32 rpm)
{
	u8 cmd[5] = { FAN_SET, rpm >> 24, rpm >> 16, rpm >> 8, rpm };
	int ret;

	mutex_lock(&k->lock);
	ret = i2c_master_send(k->client, cmd, sizeof(cmd));
	if (ret == sizeof(cmd))
		k->fan_rpm = rpm;
	mutex_unlock(&k->lock);
	return ret == sizeof(cmd) ? 0 : (ret < 0 ? ret : -EIO);
}

static int sgb_perf_send(enum platform_profile_option profile)
{
	u8 in[2] = { 0x80 };

	switch (profile) {
	case PLATFORM_PROFILE_QUIET:
		in[1] = PERF_QUIET;
		break;
	case PLATFORM_PROFILE_BALANCED:
		in[1] = PERF_AUTO;
		break;
	case PLATFORM_PROFILE_PERFORMANCE:
		in[1] = PERF_MAX;
		break;
	default:
		return -EOPNOTSUPP;
	}
	return sgb_ec_excmd(EC_PERF_MODE, in, sizeof(in), NULL, 0);
}

static int sgb_profile_probe(void *drvdata, unsigned long *choices)
{
	set_bit(PLATFORM_PROFILE_QUIET, choices);
	set_bit(PLATFORM_PROFILE_BALANCED, choices);
	set_bit(PLATFORM_PROFILE_PERFORMANCE, choices);
	return 0;
}

static int sgb_profile_get(struct device *dev, enum platform_profile_option *profile)
{
	struct sgb_kbd *k = dev_get_drvdata(dev);

	*profile = k->profile;
	return 0;
}

static int sgb_profile_set(struct device *dev, enum platform_profile_option profile)
{
	struct sgb_kbd *k = dev_get_drvdata(dev);
	int ret = sgb_perf_send(profile);

	if (!ret)
		k->profile = profile;
	return ret;
}

static const struct platform_profile_ops sgb_profile_ops = {
	.probe = sgb_profile_probe,
	.profile_get = sgb_profile_get,
	.profile_set = sgb_profile_set,
};

static umode_t sgb_hwmon_visible(const void *data, enum hwmon_sensor_types type, u32 attr, int channel)
{
	return type == hwmon_fan && attr == hwmon_fan_target ? 0644 : 0;
}

static int sgb_hwmon_read(struct device *dev, enum hwmon_sensor_types type, u32 attr, int channel, long *val)
{
	struct sgb_kbd *k = dev_get_drvdata(dev);

	*val = k->fan_rpm;
	return 0;
}

static int sgb_hwmon_write(struct device *dev, enum hwmon_sensor_types type, u32 attr, int channel, long val)
{
	struct sgb_kbd *k = dev_get_drvdata(dev);

	return sgb_fan_send(k, clamp_val(val, 0, FAN_MAX));
}

static const struct hwmon_ops sgb_hwmon_ops = {
	.is_visible = sgb_hwmon_visible,
	.read = sgb_hwmon_read,
	.write = sgb_hwmon_write,
};

static const struct hwmon_channel_info *const sgb_hwmon_info[] = {
	HWMON_CHANNEL_INFO(fan, HWMON_F_TARGET),
	NULL
};

static const struct hwmon_chip_info sgb_hwmon_chip = {
	.ops = &sgb_hwmon_ops,
	.info = sgb_hwmon_info,
};

static int sgb_kbd_set(struct led_classdev *led, enum led_brightness value)
{
	struct sgb_kbd *k = container_of(led, struct sgb_kbd, led);

	k->level = levels ? min_t(u8, value, KBD_MAX) : (value ? KBD_MAX : 0);
	return sgb_kbd_send(k, k->level);
}

/*
 * Fn+F9. The HID side and the EC side probe independently, so the hotkey work finds the EC
 * instance through sgb_kbd_dev (set while the i2c device is bound).
 */
static DEFINE_MUTEX(sgb_kbd_dev_lock);
static struct sgb_kbd *sgb_kbd_dev;

static void sgb_kbd_hotkey_work(struct work_struct *work)
{
	struct sgb_kbd *k;
	unsigned int next;

	mutex_lock(&sgb_kbd_dev_lock);
	k = sgb_kbd_dev;
	if (k) {
		next = k->led.brightness >= k->led.max_brightness ? 0 : k->led.brightness + 1;
		led_set_brightness_sync(&k->led, next);
		led_classdev_notify_brightness_hw_changed(&k->led, next);
	}
	mutex_unlock(&sgb_kbd_dev_lock);
}
static DECLARE_WORK(sgb_kbd_hotkey, sgb_kbd_hotkey_work);

static void sgb_kbd_unpublish(void *data)
{
	mutex_lock(&sgb_kbd_dev_lock);
	sgb_kbd_dev = NULL;
	mutex_unlock(&sgb_kbd_dev_lock);
}

static int sgb_hid_raw_event(struct hid_device *hdev, struct hid_report *report, u8 *data, int size)
{
	if (size > 1 && data[0] == HOTKEY_REPORT) {
		if (memchr(data + 1, HOTKEY_KBD, size - 1))
			schedule_work(&sgb_kbd_hotkey);
		else
			hid_dbg(hdev, "vendor hotkey report %*ph\n", size, data);
	}
	return 0;			/* the keyboard keeps working as before */
}

static int sgb_hid_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	int ret;

	/*
	 * As hid-generic does: one input device per application collection (Keyboard, Consumer Control,
	 * Wireless Radio Control, System Control). Merged into one device, the keyboard stops typing and the
	 * Fn brightness/volume keys stop working.
	 */
	hdev->quirks |= HID_QUIRK_INPUT_PER_APP;
	ret = hid_parse(hdev);
	return ret ?: hid_hw_start(hdev, HID_CONNECT_DEFAULT);
}

static const struct hid_device_id sgb_hid_ids[] = {
	{ HID_I2C_DEVICE(0x0cf2, 0x9050) },	/* ENE keyboard of the Galaxy Book4 Edge */
	{ }
};
MODULE_DEVICE_TABLE(hid, sgb_hid_ids);

static struct hid_driver sgb_hid_driver = {
	.name = "samsung-galaxybook-kbd",
	.id_table = sgb_hid_ids,
	.probe = sgb_hid_probe,
	.raw_event = sgb_hid_raw_event,
};

static int sgb_kbd_probe(struct i2c_client *client)
{
	struct sgb_kbd *k;
	int level, ret;

	k = devm_kzalloc(&client->dev, sizeof(*k), GFP_KERNEL);
	if (!k)
		return -ENOMEM;
	k->client = client;
	mutex_init(&k->lock);

	level = sgb_kbd_get(k);		/* waits for the battery driver; also proves the EC answers */
	if (level < 0)
		return dev_err_probe(&client->dev, level, "EC does not answer the backlight query\n");

	k->led.name = "samsung-galaxybook::kbd_backlight";
	k->led.max_brightness = levels ? KBD_MAX : 1;
	k->led.brightness = levels ? level : !!level;
	k->led.brightness_set_blocking = sgb_kbd_set;
	/* sets 0 on suspend, restores on resume; HW_CHANGED for the Fn+F9 OSD */
	k->led.flags = LED_CORE_SUSPENDRESUME | LED_BRIGHT_HW_CHANGED;
	ret = devm_led_classdev_register(&client->dev, &k->led);
	if (ret)
		return ret;

	mutex_lock(&sgb_kbd_dev_lock);
	sgb_kbd_dev = k;
	mutex_unlock(&sgb_kbd_dev_lock);
	ret = devm_add_action_or_reset(&client->dev, sgb_kbd_unpublish, k);
	if (ret)
		return ret;

	i2c_set_clientdata(client, k);
	if (IS_ERR(devm_hwmon_device_register_with_info(&client->dev, "samsung_galaxybook_ec", k,
							&sgb_hwmon_chip, NULL)))
		dev_warn(&client->dev, "no hwmon fan control\n");

	/* The EC cannot report its mode; start from Optimized, as Windows boots. */
	k->profile = PLATFORM_PROFILE_BALANCED;
	if (sgb_perf_send(k->profile) ||
	    IS_ERR(devm_platform_profile_register(&client->dev, "samsung-galaxybook", k, &sgb_profile_ops)))
		dev_warn(&client->dev, "no performance modes\n");
	return 0;
}

static int sgb_kbd_resume(struct device *dev)
{
	struct sgb_kbd *k = dev_get_drvdata(dev);

	/* The EC may have been reset over suspend; give it the fan target again. */
	if (k->fan_rpm)
		sgb_fan_send(k, k->fan_rpm);
	sgb_perf_send(k->profile);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(sgb_kbd_pm, NULL, sgb_kbd_resume);

static const struct of_device_id sgb_kbd_of_match[] = {
	{ .compatible = "samsung,galaxy-book4-edge-kbd-backlight" },
	{ }
};
MODULE_DEVICE_TABLE(of, sgb_kbd_of_match);

static struct i2c_driver sgb_kbd_driver = {
	.driver = {
		.name = "samsung-galaxybook-kbd",
		.of_match_table = sgb_kbd_of_match,
		.pm = pm_sleep_ptr(&sgb_kbd_pm),
	},
	.probe = sgb_kbd_probe,
};

static int __init sgb_kbd_init(void)
{
	int ret = i2c_add_driver(&sgb_kbd_driver);

	if (ret)
		return ret;
	ret = hid_register_driver(&sgb_hid_driver);
	if (ret)
		i2c_del_driver(&sgb_kbd_driver);
	return ret;
}

static void __exit sgb_kbd_exit(void)
{
	hid_unregister_driver(&sgb_hid_driver);
	i2c_del_driver(&sgb_kbd_driver);
	cancel_work_sync(&sgb_kbd_hotkey);
}
module_init(sgb_kbd_init);
module_exit(sgb_kbd_exit);

MODULE_DESCRIPTION("Samsung Galaxy Book4 Edge keyboard backlight, fan and performance modes (EC)");
MODULE_LICENSE("GPL");
