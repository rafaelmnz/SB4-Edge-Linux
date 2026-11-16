// SPDX-License-Identifier: GPL-2.0
/*
 * sb4_dtbo: development helper. Applies a device-tree overlay from /lib/firmware at load and
 * removes it at unload, so DT changes can be tried on the running laptop without reflashing.
 *   insmod sb4_dtbo.ko name=sb4edge/charger.dtbo,sb4edge/camera.dtbo
 */
#include <linux/firmware.h>
#include <linux/module.h>
#include <linux/of.h>

static char *name[8];
static int count;
module_param_array(name, charp, &count, 0444);
MODULE_PARM_DESC(name, "overlay files under /lib/firmware, comma separated");

static int ovcs_id[8];

static void sb4_dtbo_remove_all(void)
{
	int i;

	for (i = count - 1; i >= 0; i--)
		if (ovcs_id[i])
			of_overlay_remove(&ovcs_id[i]);
}

static int __init sb4_dtbo_init(void)
{
	const struct firmware *fw;
	int i, ret;

	if (!count)
		return -EINVAL;
	for (i = 0; i < count; i++) {
		ret = request_firmware(&fw, name[i], NULL);
		if (ret)
			goto err;
		ret = of_overlay_fdt_apply(fw->data, fw->size, &ovcs_id[i], NULL);
		release_firmware(fw);
		if (ret) {
			pr_err("sb4_dtbo: applying %s failed: %d\n", name[i], ret);
			goto err;
		}
		pr_info("sb4_dtbo: applied %s (id %d)\n", name[i], ovcs_id[i]);
	}
	return 0;
err:
	sb4_dtbo_remove_all();
	return ret;
}

static void __exit sb4_dtbo_exit(void)
{
	sb4_dtbo_remove_all();
	pr_info("sb4_dtbo: overlays removed\n");
}

module_init(sb4_dtbo_init);
module_exit(sb4_dtbo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Apply a DT overlay from a firmware file (development helper)");
