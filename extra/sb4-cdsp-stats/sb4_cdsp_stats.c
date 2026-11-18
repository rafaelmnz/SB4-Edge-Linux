// SPDX-License-Identifier: GPL-2.0-only
/*
 * Qualcomm SysMon SMEM layout: drivers/soc/qcom/sysmon_subsystem_stats.c
 * in the Qualcomm downstream kernel. Q6 average load is in thousands of
 * cycles/sec; its clock vote is in kHz. The result is compute DSP load.
 * Reading shared firmware statistics never wakes the DSP.
 */
#include <linux/module.h>
#include <asm/arch_timer.h>
#include <linux/math64.h>

#define CDSP_HOST 5
#define SYSMON_STATS 634
#define Q6_LOAD 1
#define Q6_CLOCK_VOTE 2
#include <linux/io.h>
#include <linux/of.h>
#include <linux/soc/qcom/smem.h>

static int sample_get(char *buf, const struct kernel_param *kp)
{
	size_t size, pos = 0;
	void *data;
	u64 timestamp, now;
	u32 load = 0, freq = 0, lo = 0, hi = 0;
	bool have_load = false, have_clock = false;

	data = qcom_smem_get(CDSP_HOST, SYSMON_STATS, &size);
	if (IS_ERR(data))
		return PTR_ERR(data);
	while (size - pos >= 4) {
		void __iomem *entry = (void __iomem *)data + pos;
		u32 hdr = readl(entry);
		u32 len = (hdr >> 16) & 0xfff;

		if (len < 4 || len % 4 || len > size - pos)
			break;
		switch (hdr >> 28) {
		case Q6_LOAD:
			if (len >= 16) {
				load = readl(entry + 4);
				lo = readl(entry + 8);
				hi = readl(entry + 12);
				/* Discard a sample updated during the read. */
				have_load = lo == readl(entry + 8) &&
					    hi == readl(entry + 12) &&
					    load == readl(entry + 4);
			}
			break;
		case Q6_CLOCK_VOTE:
			if (len >= 8) {
				freq = readl(entry + 4);
				have_clock = true;
			}
			break;
		}
		pos += len;
	}
	if (!have_load || !have_clock)
		return -ENODATA;
	timestamp = ((u64)hi << 32) | lo;
	now = __arch_counter_get_cntvct();
	/* No sample yet: the DSP has not run anything since boot, so it is idle. */
	if (!timestamp)
		return sysfs_emit(buf, "0\n");
	if (timestamp > now)
		return -ENODATA;
	/* SysMon stops updating when idle. Match its 100 ms freshness rule. */
	if (now - timestamp > arch_timer_get_cntfrq() / 10)
		return sysfs_emit(buf, "0\n");
	if (!freq)
		return -ENODATA;
	return sysfs_emit(buf, "%llu\n",
			  min_t(u64, 1000, div_u64((u64)load * 1000, freq)));
}
static const struct kernel_param_ops sample_ops = { .get = sample_get };
module_param_cb(load_permille, &sample_ops, NULL, 0444);

static int __init stats_init(void)
{
	return of_machine_is_compatible("qcom,x1e80100") ? 0 : -ENODEV;
}
MODULE_PARM_DESC(load_permille, "Hexagon Q6 load per thousand of its clock vote");

static void __exit stats_exit(void) {}
module_init(stats_init);
module_exit(stats_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only Snapdragon X Elite CDSP SysMon statistics");
