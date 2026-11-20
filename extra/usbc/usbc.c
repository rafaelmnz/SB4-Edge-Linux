// SPDX-License-Identifier: GPL-2.0
/*
 * USB-C power roles for the Samsung Galaxy Book4 Edge 14.
 *
 * Each USB-C port has a Samsung S2MM006 PD controller at 0x33 on its own I2C
 * bus (i2c@a84000: port 0, i2c@a9c000: port 1). After boot the controller
 * only detects a new partner and then waits for the host, which on Windows is
 * EmuEc.sys. Linux has no driver for it, so this does the same:
 *
 *  - a device (sink) is detected but gets no VBUS: command 0x09, provider on
 *  - a device we power is removed: command 0x00, all switches off (else VBUS
 *    stays on and a charger plugged in next can't attach)
 *  - a charger (source) attaches but its input switch stays open: command
 *    0x12, consumer on; then ask for the highest fixed PDO up to 20 V, at
 *    most twice per attach
 *
 * For SuperSpeed, the port's PS8830 retimer has to know the plug orientation
 * before the device gets VBUS: it is written to the gb4e_typec module's
 * /sys/devices/platform/gb4e-typec/portN first, and set to none on removal.
 * Without the module, devices run at USB 2.0 speed.
 *
 * The commands are EmuEc.sys's: its switch function writes 0x00, 0x09 or 0x12
 * to register 0x4E. Registers are 16-bit. Others used here, from
 * ciscobugger/book4-edge-linux (reports/ec/07-pdic-s2mm006.md) and tests on
 * this machine: 0x11 the partner (high nibble 2: a sink, 0x2e while it waits
 * for VBUS; 1: a source, 0x1b for a charger; EmuEc.sys's CC interrupt handler
 * tests the same nibble), 0x0E attach (0x10 while a sink waits for VBUS, but
 * a charger can show it too; 0x01 or 0x11 with a powered sink; 0x05 with the
 * provider on: the device is gone), 0x12 (bits 0-1:
 * the active CC pin, 1 normal and 2 reverse, while a partner waits; EmuEc.sys's
 * CC interrupt handler tests the same bits), 0x1C switches
 * (bit 0 provider, 0x0a consumer closed), 0x0900 the received
 * Source_Capabilities (empty without a source), 0x0080 the message to send,
 * 0x50 bit 6 sends it, 0x06A0 the Request in force.
 *
 * sb4edge: DisplayPort alt mode, from EmuEc.sys (s2mm006_int_altmode, s2mm006_alt_control,
 * s2mm006_check_ufpu_status). The controller runs Discover Identity/SVIDs/Modes, Enter Mode and
 * DP Configure itself, but only when the host lets it: 0x50 (PD_CTRL1) bit 0 StartAlt starts discovery,
 * bit 1 ContinueAlt lets it enter the DP mode it found, and the pin assignment it configures is
 * written to 0x51 bits 0-2 (1 A, 2 C, 3 D, 4 E, 5 B, 6 F). Progress is in 0x1A | 0x57 << 8 (cleared
 * by writing 0): 0x04 Discover Mode (reply at 0x0A40), 0x08 Enter Mode (0x0A60), 0x10 Exit Mode,
 * 0x20 DP Status (0x0AC0), 0x40 DP Configure (0x0AE0), 0x80 Attention (0x0AA0). Each reply is a
 * 4-byte header, the VDM header (byte 4 bits 0-4 the command, bytes 6-7 the SVID) and the VDOs.
 * The DP mux, retimer and HPD are then set through pmic_glink_altmode's inject file (kernel patch
 * 0016), as the ADSP would on other X1E laptops.
 */
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>

#define ADDR		0x33
#define POLL_MS		150	/* a waiting device shows 0x10 for ~0.33 s of every ~3.7 s */
#define SETTLE		1.0	/* s after a command before acting on that port again */
#define GONE_POLLS	2	/* polls a powered port must look empty before VBUS goes off */
#define MAX_MV		20000	/* the charger's input limit */
#define MAX_TX		2	/* PD transmissions per attach */
#define TX_GAP		30.0	/* s between transmissions, any port */
#define FRESH		1.0	/* s a partner or orientation reading stays valid */
#define ORIENT_WAIT	5.0	/* s to wait for one before powering a device anyway */
#define ALT_DELAY	1.5	/* s after a PD contract before letting the controller start alt modes */
#define INJECT		"/sys/bus/auxiliary/devices/pmic_glink.altmode.0/inject"
#define DP_SID		0xff01
/*
 * HPD high is passed on only once the partner has been quiet this long. A DP-to-HDMI adapter reports
 * HPD before it has found the monitor behind it (sink count 0); msm then gives up on the EDID and the
 * link (-ENOTCONN), and the IRQ_HPD that follows is lost: the HPD bridge only carries connected or not.
 */
#define HPD_SETTLE	2.0

static int dump_only;

struct port {
	int n, fd, gone, tx;
	int orient;		/* 0x12 bits 0-1: 0 unknown, 1 normal, 2 reverse */
	int orient_set;		/* what the retimer was last told */
	double cmd_t, check_t, orient_t, wait_t;
	double sink_t, source_t;	/* when 0x11 last showed a sink, a source */
	/* DisplayPort alt mode */
	double attach_t;	/* when we started powering a device or took a charger's power */
	int alt_started;	/* StartAlt written for this attach */
	int dp_pins;		/* partner's UFP_D pin assignments (bit 0 A .. bit 5 F) */
	char dp_pin;		/* pin configured, 'C' or 'D'; 0: none */
	int dp_on;		/* told the kernel DP is on */
	int hpd;		/* partner's HPD */
	int hpd_sent;		/* HPD state the kernel has */
	double hpd_t;		/* last DP status/attention from the partner */
};

static double last_tx = -TX_GAP;

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* Test builds read a fake tree: -DSYSFS_ROOT='"/tmp/fx"' */
#ifndef SYSFS_ROOT
#define SYSFS_ROOT ""
#endif

/*
 * Is block device maj:min on a disk behind this USB controller? Follows stacked devices down to the disks:
 * device mapper / md (LUKS, LVM, RAID: holders list their backing devices in slaves/) and loop devices
 * (backing file -> the device of the filesystem holding it).
 */
static int dev_behind(unsigned int maj, unsigned int min, const char *want, int depth)
{
	char path[PATH_MAX], real[PATH_MAX], sub[2 * PATH_MAX];
	DIR *d;
	struct dirent *e;
	FILE *f;
	struct stat st;
	int found = 0;

	if (!maj || depth > 8)
		return depth > 8;	/* too deep: be safe */
	snprintf(path, sizeof(path), SYSFS_ROOT "/sys/dev/block/%u:%u", maj, min);
	if (!realpath(path, real))
		return 0;
	if (strstr(real, want))
		return 1;
	snprintf(sub, sizeof(sub), "%s/slaves", real);
	d = opendir(sub);
	while (d && !found && (e = readdir(d))) {
		unsigned int a, b;

		if (e->d_name[0] == '.')
			continue;
		snprintf(sub, sizeof(sub), "%s/slaves/%s/dev", real, e->d_name);
		f = fopen(sub, "r");
		if (f && fscanf(f, "%u:%u", &a, &b) == 2)
			found = dev_behind(a, b, want, depth + 1);
		if (f)
			fclose(f);
	}
	if (d)
		closedir(d);
	snprintf(sub, sizeof(sub), "%s/loop/backing_file", real);
	if (!found && (f = fopen(sub, "r"))) {
		if (fgets(path, sizeof(path), f)) {
			path[strcspn(path, "\n")] = 0;
			if (stat(path, &st) == 0)
				found = dev_behind(major(st.st_dev), minor(st.st_dev), want, depth + 1);
		}
		fclose(f);
	}
	return found;
}

/*
 * Is a filesystem mounted, or swap active, from a disk behind this USB controller (e.g. the live USB stick, or an
 * encrypted external disk)? Then a device on the port must keep its power.
 */
static int disk_mounted_behind(const char *usb)
{
	char line[1024], want[64], name[512];
	unsigned int maj, min;
	struct stat st;
	int found = 0;
	FILE *f = fopen(SYSFS_ROOT "/proc/self/mountinfo", "r");

	if (!f)
		return 1;	/* unknown: be safe */
	snprintf(want, sizeof(want), "/%s.usb/", usb);
	while (!found && fgets(line, sizeof(line), f))
		if (sscanf(line, "%*s %*s %u:%u", &maj, &min) == 2)
			found = dev_behind(maj, min, want, 0);
	fclose(f);
	f = fopen(SYSFS_ROOT "/proc/swaps", "r");
	while (f && !found && fgets(line, sizeof(line), f)) {
		/* "Filename Type Size Used Priority": a partition (st_rdev) or a swap file (its filesystem's st_dev) */
		if (sscanf(line, "%511s", name) != 1 || name[0] != '/' || stat(name, &st) != 0)
			continue;
		found = S_ISBLK(st.st_mode) ? dev_behind(major(st.st_rdev), minor(st.st_rdev), want, 0)
					    : dev_behind(major(st.st_dev), minor(st.st_dev), want, 0);
	}
	if (f)
		fclose(f);
	return found;
}

/* I2C bus numbers follow probe order, so find the controller by address. */
static int bus_of(const char *controller)
{
	char path[PATH_MAX], real[PATH_MAX], want[64];
	struct dirent *e;
	DIR *d = opendir("/sys/bus/i2c/devices");
	int bus = -1;

	if (!d)
		return -1;
	snprintf(want, sizeof(want), "/%s.i2c/", controller);
	while (bus < 0 && (e = readdir(d))) {
		if (strncmp(e->d_name, "i2c-", 4))
			continue;
		snprintf(path, sizeof(path), "/sys/bus/i2c/devices/%s", e->d_name);
		if (!realpath(path, real))
			continue;
		strncat(real, "/", sizeof(real) - strlen(real) - 1);
		if (strstr(real, want))
			bus = atoi(e->d_name + 4);
	}
	closedir(d);
	return bus;
}

static int xfer(struct port *p, uint8_t *w, int wlen, uint8_t *r, int rlen)
{
	struct i2c_msg msgs[2] = {
		{ .addr = ADDR, .flags = 0, .len = wlen, .buf = w },
		{ .addr = ADDR, .flags = I2C_M_RD, .len = rlen, .buf = r },
	};
	struct i2c_rdwr_ioctl_data data = { .msgs = msgs, .nmsgs = rlen ? 2 : 1 };

	return ioctl(p->fd, I2C_RDWR, &data) < 0 ? -1 : 0;
}

static int rd(struct port *p, uint16_t reg, uint8_t *buf, int n)
{
	uint8_t a[2] = { reg >> 8, reg & 0xff };

	return xfer(p, a, 2, buf, n);
}

static int rd1(struct port *p, uint16_t reg)
{
	uint8_t v;

	return rd(p, reg, &v, 1) ? -1 : v;
}

static int wr(struct port *p, uint16_t reg, uint8_t val)
{
	uint8_t a[3] = { reg >> 8, reg & 0xff, val };

	return xfer(p, a, 3, NULL, 0);
}

static int set_bits(struct port *p, uint16_t reg, uint8_t mask, uint8_t val)
{
	int v = rd1(p, reg);

	if (v < 0)
		return -1;
	return wr(p, reg, (v & ~mask) | val);
}

static int orientation_of(struct port *p)
{
	return p->orient_set > 0 ? p->orient_set : p->orient;
}

/* Hand the DP state to pmic_glink_altmode (mux, retimer, HPD). */
static void inject(struct port *p, const char *state)
{
	static const char *const names[] = { "none", "normal", "reverse" };
	char line[64];
	FILE *f = fopen(INJECT, "w");

	snprintf(line, sizeof(line), "%d %s %s", p->n, names[orientation_of(p)], state);
	if (!f || fputs(line, f) < 0 || fclose(f)) {
		printf("port %d: inject \"%s\" failed\n", p->n, line);
		return;
	}
	printf("port %d: inject %s\n", p->n, line);
}

static void dp_report(struct port *p, int hpd, int irq)
{
	char state[16];

	snprintf(state, sizeof(state), "dp %c %d %d", p->dp_pin, hpd, irq);
	inject(p, state);
	p->dp_on = 1;
	p->hpd_sent = hpd;
}

/* Pass HPD on: low at once, high once the partner has settled (HPD_SETTLE). */
static void hpd_update(struct port *p, double t)
{
	if (!p->dp_on || p->hpd == p->hpd_sent)
		return;
	if (p->hpd && t - p->hpd_t < HPD_SETTLE)
		return;
	dp_report(p, p->hpd, 0);
}

/*
 * Partner left: drop HPD first, with the lanes still in DP mode, and give msm time to shut the
 * output down; only then put the lanes in safe mode. Switching the PHY away while msm still drives
 * the link resets the whole machine.
 */
static void alt_reset(struct port *p)
{
	if (p->dp_on) {
		struct timespec settle = { 2, 0 };	/* GNOME turns the output off on the hotplug event */

		if (p->hpd_sent)
			dp_report(p, 0, 0);
		nanosleep(&settle, NULL);
		inject(p, "safe");
	}
	p->alt_started = 0;
	p->dp_pins = 0;
	p->dp_pin = 0;
	p->dp_on = 0;
	p->hpd = 0;
	p->hpd_sent = 0;
	p->hpd_t = 0;
	p->attach_t = 0;
}

/* The pin we configure: 4-lane C when the partner has it (full bandwidth), else D (2 lanes + USB 3). */
static char choose_pin(int pins)
{
	if (pins & 0x04)
		return 'C';
	if (pins & 0x08)
		return 'D';
	return 0;
}

static const uint8_t pin_code[] = { ['A'] = 1, ['B'] = 5, ['C'] = 2, ['D'] = 3, ['E'] = 4, ['F'] = 6 };

/*
 * The service (re)started with a partner already in DP mode: take the pins from the stored Discover
 * Mode reply and the pin from 0x51, which the controller configured before.
 */
static void dp_recover(struct port *p)
{
	uint8_t b[12];
	int v, c;

	if (rd(p, 0x0A40, b, 12) || (b[4] & 0x1f) != 3 || (b[6] | b[7] << 8) != DP_SID)
		return;
	if (!orientation_of(p)) {
		/* 0x12 keeps the CC pin while the partner is powered too (seen: 0x06, reverse) */
		int r = rd1(p, 0x12);

		if (r < 0 || !(r & 3) || (r & 3) == 3) {
			printf("port %d: DP adapter attached, orientation unknown (0x12=0x%02x)\n", p->n, r);
			return;
		}
		p->orient = r & 3;
		p->orient_t = now();
	}
	p->dp_pins = b[8] & 0x40 ? b[10] : b[9];
	v = rd1(p, 0x51);
	for (c = 'A'; v > 0 && c <= 'F'; c++)
		if (pin_code[c] == (v & 7) && (c == 'C' || c == 'D')) {
			p->dp_pin = c;
			p->dp_on = 1;	/* configured already: report the mux with the next HPD update */
			p->hpd_sent = -1;
			p->alt_started = 1;
		}
	printf("port %d: DP mode already active (pins 0x%02x, pin %c)\n", p->n, p->dp_pins,
	       p->dp_pin ? p->dp_pin : '-');
}

/* At start: a partner already configured for DP gets its mux now and its HPD from the last status. */
static void dp_resume(struct port *p)
{
	uint8_t b[12];

	dp_recover(p);
	if (!p->dp_pin)
		return;
	if (!rd(p, 0x0AA0, b, 12) && (b[4] & 0x1f) == 6)
		p->hpd = !!(b[8] & 0x80);
	else if (!rd(p, 0x0AC0, b, 12) && (b[4] & 0x1f) == 0x10)
		p->hpd = !!(b[8] & 0x80);
	p->hpd_t = now();
	dp_report(p, 0, 0);
}

static void dp_status(struct port *p, uint32_t vdo, int irq_allowed, double t)
{
	int hpd = !!(vdo & 0x80), irq = irq_allowed && (vdo & 0x100);

	printf("port %d: DP status 0x%08x (connected %d, multi-function %d, hpd %d, irq %d)\n", p->n,
	       vdo, vdo & 3, !!(vdo & 0x10), hpd, irq);
	if (!p->dp_pins)
		dp_recover(p);
	if (!p->dp_pin) {
		char pin = choose_pin(p->dp_pins);

		if (!pin) {
			printf("port %d: partner offers no pin C or D (0x%02x)\n", p->n, p->dp_pins);
			return;
		}
		if (set_bits(p, 0x51, 0x07, pin_code[(int)pin]))
			return;
		p->dp_pin = pin;
		printf("port %d: pin %c selected\n", p->n, pin);
	}
	p->hpd = hpd;
	p->hpd_t = t;
	if (p->dp_on && p->hpd_sent == -1) {
		/* recovered: put the mux in DP mode now, HPD follows from hpd_update() */
		dp_report(p, 0, 0);
	}
}

/* Poll the controller's alt mode progress (EmuEc.sys does this from the PD_INT2 interrupt). */
static void altmode(struct port *p, double t)
{
	uint8_t b[12];
	int lo, hi, st;
	uint32_t vdo;

	if (!p->alt_started && p->attach_t && t - p->attach_t >= ALT_DELAY) {
		if (!set_bits(p, 0x50, 0x01, 0x01)) {
			p->alt_started = 1;
			printf("port %d: alt modes started (0x50=0x%02x)\n", p->n, rd1(p, 0x50));
		}
	}
	hpd_update(p, t);
	lo = rd1(p, 0x1A);
	hi = rd1(p, 0x57);
	if (lo <= 0 && hi <= 0)
		return;
	if (lo > 0)
		wr(p, 0x1A, 0);
	if (hi > 0)
		wr(p, 0x57, 0);
	st = (lo > 0 ? lo : 0) | (hi > 0 ? hi : 0) << 8;
	printf("port %d: alt mode state 0x%03x\n", p->n, st);

	if (st & 0x04 && !rd(p, 0x0A40, b, 12) && (b[4] & 0x1f) == 3) {
		int svid = b[6] | b[7] << 8;

		vdo = b[8] | b[9] << 8 | b[10] << 16 | (uint32_t)b[11] << 24;
		printf("port %d: Discover Mode svid 0x%04x vdo 0x%08x\n", p->n, svid, vdo);
		if (svid == DP_SID && (b[0] & 7) > 1 && (vdo & 3) != 2) {
			p->dp_pins = vdo & 0x40 ? b[10] : b[9];
			printf("port %d: DisplayPort partner, pins 0x%02x\n", p->n, p->dp_pins);
			if (!set_bits(p, 0x50, 0x02, 0x02))
				printf("port %d: continue to Enter Mode (0x50=0x%02x)\n", p->n, rd1(p, 0x50));
		}
	}
	if (st & 0x08 && !rd(p, 0x0A60, b, 8))
		printf("port %d: Enter Mode cmd 0x%02x svid 0x%04x\n", p->n, b[4], b[6] | b[7] << 8);
	if (st & 0x10) {
		printf("port %d: Exit Mode\n", p->n);
		alt_reset(p);
		p->alt_started = 1;	/* don't restart it for this attach */
	}
	if (st & 0x20 && !rd(p, 0x0AC0, b, 12) && (b[4] & 0x1f) == 0x10)
		dp_status(p, b[8] | b[9] << 8 | b[10] << 16 | (uint32_t)b[11] << 24, 0, t);
	if (st & 0x40 && !rd(p, 0x0AE0, b, 8) && (b[4] & 0x1f) == 0x11) {
		printf("port %d: DP Configure %s\n", p->n, (const char *[]){ "REQ", "ACK", "NAK", "BUSY" }[b[4] >> 6]);
		if (b[4] >> 6 == 1 && p->dp_pin)
			dp_report(p, 0, 0);	/* mux to DP; HPD follows from hpd_update() */
	}
	if (st & 0x80 && !rd(p, 0x0AA0, b, 12) && (b[4] & 0x1f) == 6 && (b[6] | b[7] << 8) == DP_SID)
		dp_status(p, b[8] | b[9] << 8 | b[10] << 16 | (uint32_t)b[11] << 24, 1, t);
}

/* Tell the retimer the plug orientation (1 normal, 2 reverse, 0 none). */
static void set_orientation(struct port *p, int orient)
{
	static const char *const names[] = { "none", "normal", "reverse" };
	char path[64];
	FILE *f;

	if (orient == p->orient_set)
		return;
	snprintf(path, sizeof(path), "/sys/devices/platform/gb4e-typec/port%d", p->n);
	f = fopen(path, "w");
	if (!f)
		return;
	if (fputs(names[orient], f) < 0 || fclose(f)) {
		printf("port %d: setting orientation %s failed\n", p->n, names[orient]);
		return;
	}
	p->orient_set = orient;
	if (orient)
		printf("port %d: orientation %s\n", p->n, names[orient]);
}

static int have_retimers(void)
{
	return access("/sys/devices/platform/gb4e-typec/port0", W_OK) == 0;
}

static void command(struct port *p, uint8_t val, const char *what, int a, int s)
{
	if (wr(p, 0x4E, val))
		return;
	p->cmd_t = now();
	printf("port %d: %s (0x0E=0x%02x 0x1C=0x%02x)\n", p->n, what, a, s);
}

/* PDOs of the received Source_Capabilities; returns how many (0: none). */
static int caps(struct port *p, uint32_t pdo[7])
{
	uint8_t b[32];
	int h, n, i;

	if (rd(p, 0x0900, b, sizeof(b)))
		return 0;
	h = b[0] | b[1] << 8;
	n = h >> 12 & 7;
	if ((h & 0xf) != 1)
		return 0;
	for (i = 0; i < n; i++)
		pdo[i] = b[4 + 4 * i] | b[5 + 4 * i] << 8 | b[6 + 4 * i] << 16 |
			 (uint32_t)b[7 + 4 * i] << 24;
	return n;
}

/* Type, object count and object position of an 8-byte PD message at reg. */
static int request(struct port *p, uint16_t reg, int *type, int *nobj, int *pos)
{
	uint8_t b[8];
	int h;

	if (rd(p, reg, b, sizeof(b)))
		return -1;
	h = b[0] | b[1] << 8;
	*type = h & 0xf;
	*nobj = h >> 12 & 7;
	*pos = b[7] >> 4;
	return 0;
}

/* Ask for the highest fixed PDO up to MAX_MV if the contract is lower. */
static void upgrade(struct port *p, double t)
{
	uint32_t pdo[7], rdo;
	int type, nobj, cur, pos = 0, mv = 0, ma = 0, n, i, ctl, spos;

	if (p->tx >= MAX_TX || t - last_tx < TX_GAP)
		return;
	if (request(p, 0x06A0, &type, &nobj, &cur) || type != 2)
		return;
	n = caps(p, pdo);
	for (i = 0; i < n; i++) {
		int v = (pdo[i] >> 10 & 0x3ff) * 50;

		if (pdo[i] >> 30 == 0 && v > mv && v <= MAX_MV) {
			mv = v;
			pos = i + 1;
			ma = pdo[i] & 0x3ff;
		}
	}
	if (pos <= cur || mv <= 5000) {
		p->tx = MAX_TX; /* nothing better on offer; done for this attach */
		return;
	}
	if (request(p, 0x0080, &type, &nobj, &spos) || type != 2 || nobj != 1 || spos != pos) {
		/*
		 * The controller doesn't always stage the Request itself; write it
		 * in the form it uses: header 0x1002, USB communication and
		 * no-suspend set.
		 */
		uint8_t m[8] = { 0x02, 0x10, 0x00, 0x00 };

		rdo = (uint32_t)pos << 28 | 1 << 25 | 1 << 24 | ma << 10 | ma;
		for (i = 0; i < 4; i++)
			m[4 + i] = rdo >> (8 * i);
		for (i = 0; i < 8; i++)
			if (wr(p, 0x0080 + i, m[i]))
				return;
		if (request(p, 0x0080, &type, &nobj, &spos) || type != 2 || nobj != 1 ||
		    spos != pos) {
			printf("port %d: staging a Request for PDO %d failed\n", p->n, pos);
			p->tx = MAX_TX;
			return;
		}
	}
	ctl = rd1(p, 0x50);
	if (ctl < 0 || ctl & 0x40) /* transmitter busy */
		return;
	if (wr(p, 0x50, ctl | 0x40))
		return;
	p->tx++;
	last_tx = t;
	p->check_t = t + 2;
	printf("port %d: requested PDO %d (%d mV, %d mA), contract was PDO %d\n",
	       p->n, pos, mv, ma * 10, cur);
}

static int fresh_orient(struct port *p, double t)
{
	return p->orient && t - p->orient_t < FRESH ? p->orient : 0;
}

static void step(struct port *p, double t)
{
	uint32_t pdo[7];
	int a = rd1(p, 0x0E), s = rd1(p, 0x1C), type, nobj, pos;

	if (a < 0 || s < 0)
		return;
	if (a == 0)
		p->tx = 0;
	altmode(p, t);
	if (p->check_t && t >= p->check_t) {
		p->check_t = 0;
		if (!request(p, 0x06A0, &type, &nobj, &pos))
			printf("port %d: contract now PDO %d\n", p->n, pos);
	}
	{
		/* 0x11's high nibble says what is attached, when it says anything. */
		int r = rd1(p, 0x11);

		if (r >> 4 == 2)
			p->sink_t = t;
		else if (r >> 4 == 1)
			p->source_t = t;
	}
	if (s == 0) {
		/* While a partner waits, 0x12 shows which CC pin it is on. */
		int r = rd1(p, 0x12);

		if (r >= 0 && (r & 3) && (r & 3) != 3) {
			p->orient = r & 3;
			p->orient_t = t;
		}
	}
	if (t - p->cmd_t < SETTLE)
		return;
	/*
	 * Nothing attached any more: drop DP and put the retimer back in reset. A DP adapter that was
	 * already powered when the service started (orient_set 0) still has DP to tear down; the
	 * controller opens the provider switch itself on unplug, so this is the only path that sees it.
	 */
	if (a == 0 && s == 0 && (p->orient_set > 0 || p->dp_on) && t - p->sink_t >= FRESH &&
	    t - p->source_t >= FRESH) {
		if (p->dp_on)
			printf("port %d: partner gone, DP off\n", p->n);
		alt_reset(p);
		set_orientation(p, 0);
	}
	/* A charger on a port we power: VBUS off at once. */
	if (s & 0x01 && t - p->source_t < FRESH) {
		command(p, 0x00, "charger on a port we power, VBUS off", a, s);
		alt_reset(p);
		set_orientation(p, 0);
		return;
	}
	/* A device we power that is removed leaves the provider switch on. */
	if (s & 0x01 && a != 0x01 && a != 0x11) {
		if (++p->gone >= GONE_POLLS) {
			command(p, 0x00, "device removed, VBUS off", a, s);
			alt_reset(p);
			set_orientation(p, 0);
			p->gone = 0;
		}
		return;
	}
	p->gone = 0;
	if (s == 0 && t - p->source_t >= ORIENT_WAIT && !caps(p, pdo)) {
		/*
		 * A sink, with no switch closed and no source seen for a while. Give
		 * it its orientation first; without one (or without the module), it
		 * still gets VBUS after ORIENT_WAIT, at USB 2.0 speed.
		 */
		int sink = t - p->sink_t < FRESH;
		int fresh = p->orient && t - p->orient_t < FRESH;

		if (!sink && !(a & 0x10)) {
			p->wait_t = 0;
			return;
		}
		if (!(sink && (fresh || !have_retimers()))) {
			if (!p->wait_t)
				p->wait_t = t;
			if (t - p->wait_t < ORIENT_WAIT)
				return;
		}
		p->wait_t = 0;
		set_orientation(p, sink && fresh ? p->orient : 0);
		command(p, 0x09, "device attached, VBUS on", a, s);
		alt_reset(p);
		p->attach_t = t;
		return;
	}
	p->wait_t = 0;
	if (!(s & 0x01) && t - p->source_t < FRESH && caps(p, pdo)) {
		/* A source that sent its capabilities, and we are not providing. */
		if (s != 0x0a) {
			/* keep the orientation: a USB-C monitor that charges us still needs it for DP */
			set_orientation(p, fresh_orient(p, t));
			command(p, 0x12, "charger attached, input switch on", a, s);
			alt_reset(p);
			p->attach_t = t;
		}
		else if (p->tx < MAX_TX)
			upgrade(p, t);
	}
}

static void dump(struct port *p)
{
	static const uint16_t regs[] = { 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0E, 0x11, 0x12, 0x1A, 0x1B, 0x1C,
					 0x4E, 0x50, 0x51, 0x56, 0x57 };
	static const uint16_t blocks[] = { 0x0A00, 0x0A20, 0x0A40, 0x0A60, 0x0A80, 0x0AA0, 0x0AC0, 0x0AE0 };
	uint8_t b[32];
	unsigned int i, j;

	printf("port %d:", p->n);
	for (i = 0; i < sizeof(regs) / sizeof(regs[0]); i++)
		printf(" %02x=%02x", regs[i], rd1(p, regs[i]) & 0xff);
	printf("\n");
	for (i = 0; i < sizeof(blocks) / sizeof(blocks[0]); i++) {
		if (rd(p, blocks[i], b, sizeof(b)))
			continue;
		printf("  %04x:", blocks[i]);
		for (j = 0; j < sizeof(b); j++)
			printf(" %02x", b[j]);
		printf("\n");
	}
}

int main(int argc, char **argv)
{
	static const char *const controllers[] = { "a84000", "a9c000" };
	struct timespec poll = { 0, POLL_MS * 1000000L };
	struct port ports[2];
	char dev[32];
	int i;

	setvbuf(stdout, NULL, _IOLBF, 0);
	/* --dump: print the registers this uses (reads only; 0x02-0x07 may clear interrupts) and exit */
	dump_only = argc > 1 && !strcmp(argv[1], "--dump");
	/* With the module loaded, wait until it has found the retimers. */
	for (i = 0; i < 100 && !access("/sys/module/gb4e_typec", F_OK) && !have_retimers(); i++)
		nanosleep(&poll, NULL);
	for (i = 0; i < 2; i++) {
		int bus = bus_of(controllers[i]);

		if (bus < 0) {
			fprintf(stderr, "i2c@%s not found\n", controllers[i]);
			return 1;
		}
		snprintf(dev, sizeof(dev), "/dev/i2c-%d", bus);
		ports[i] = (struct port){ .n = i, .fd = open(dev, O_RDWR), .cmd_t = -SETTLE,
					  .orient_set = -1 };
		if (ports[i].fd < 0) {
			perror(dev);
			return 1;
		}
		if (dump_only) {
			dump(&ports[i]);
			continue;
		}
		printf("port %d: 0x0E=0x%02x 0x1C=0x%02x\n", i, rd1(&ports[i], 0x0E),
		       rd1(&ports[i], 0x1C));
	}
	if (dump_only)
		return 0;
	/*
	 * sb4edge: a device already powered at start (plugged in at boot) runs at USB 2.0 until its
	 * retimer knows the plug orientation. Switch VBUS off once so it attaches again through
	 * step(), which sets the orientation; a USB 3 device only tries SuperSpeed when it powers up.
	 * Not when a filesystem is mounted from behind the port: on the Galaxy Book4 Edge 16 the live
	 * USB stick can sit on a USB-C port, and the system runs from it. Not in DP mode either.
	 */
	for (i = 0; i < 2; i++) {
		static const char *const usb[] = { "a600000", "a800000" };
		int sw = rd1(&ports[i], 0x1C);

		if (sw > 0 && sw & 0x01)
			ports[i].orient_set = 0;
		if (sw > 0 && sw & 0x01 && have_retimers() && rd1(&ports[i], 0x56) == 0) {
			if (disk_mounted_behind(usb[i])) {
				printf("port %d: powered at start, a disk behind it is mounted: left alone\n", i);
			} else {
				command(&ports[i], 0x00, "powered at start, VBUS off to attach again",
					rd1(&ports[i], 0x0E), sw);
				ports[i].orient_set = -1;
				continue;
			}
		}
		/* a partner attached before the service started (powered or charging us) can still have DP */
		if (sw > 0 && (sw & 0x01 || sw == 0x0a))
			ports[i].attach_t = now();
		/* ... and may already be in DP mode (service restart, reboot with the adapter plugged in) */
		if (sw > 0 && sw & 0x01 && rd1(&ports[i], 0x56) > 0)
			dp_resume(&ports[i]);
	}
	for (;;) {
		double t = now();

		for (i = 0; i < 2; i++)
			step(&ports[i], t);
		nanosleep(&poll, NULL);
	}
}
