/* Dump calibration (non-persistent + persistent) of one subgraph for one GKV from an AudioReach ACDB.
 * usage: caldump <acdb> <sg-id-hex> <iid-hex|0> <outdir> key=val [key=val...]   (GKV pairs, hex) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "acdb.h"

static void dump_blob(const char *tag, const uint8_t *b, uint32_t sz, uint32_t want_iid, const char *outdir)
{
	uint32_t o = 0;
	while (o + 16 <= sz) {
		uint32_t iid, pid, psz, err;
		memcpy(&iid, b + o, 4); memcpy(&pid, b + o + 4, 4); memcpy(&psz, b + o + 8, 4); memcpy(&err, b + o + 12, 4);
		if (!want_iid || iid == want_iid) {
			printf("  %s iid 0x%x pid 0x%08x size %u:", tag, iid, pid, psz);
			for (uint32_t i = 0; i < psz && i < 32; i++) printf(" %02x", b[o + 16 + i]);
			printf("%s\n", psz > 32 ? " ..." : "");
			if (outdir) {
				char fn[512]; snprintf(fn, sizeof fn, "%s/%s-iid%x-pid%08x.bin", outdir, tag, iid, pid);
				FILE *f = fopen(fn, "wb"); if (f) { fwrite(b + o, 1, 16 + psz, f); fclose(f); }
			}
		}
		o += 16 + ((psz + 7) & ~7u);
	}
}

int main(int argc, char **argv)
{
	if (argc < 6) { fprintf(stderr, "usage\n"); return 2; }
	AcdbDataFiles files = { .num_files = 1 };
	strncpy(files.acdbFiles[0].fileName, argv[1], MAX_FILENAME_LENGTH - 1);
	files.acdbFiles[0].fileNameLen = strlen(files.acdbFiles[0].fileName);
	if (acdb_init(&files, NULL)) { fprintf(stderr, "acdb_init failed\n"); return 1; }
	uint32_t sg = strtoul(argv[2], 0, 16), iid = strtoul(argv[3], 0, 16);
	const char *outdir = argv[4];
	int nk = argc - 5;
	AcdbKeyValuePair *kv = calloc(nk, sizeof *kv);
	for (int i = 0; i < nk; i++) sscanf(argv[5 + i], "%x=%x", &kv[i].key, &kv[i].value);
	AcdbGraphKeyVector gkv = { nk, kv };

	AcdbKeyVectorList ck = { 0 };
	int r = acdb_ioctl(ACDB_CMD_GET_GRAPH_CAL_KVS, &gkv, sizeof gkv, &ck, sizeof ck);
	ck.key_vector_list = malloc(ck.list_size + 16);
	r = acdb_ioctl(ACDB_CMD_GET_GRAPH_CAL_KVS, &gkv, sizeof gkv, &ck, sizeof ck);
	printf("CKVs: %u (r=%d)\n", ck.num_key_vectors, r);
	uint8_t *kp = (uint8_t *)ck.key_vector_list;
	for (uint32_t c = 0; c < ck.num_key_vectors; c++) {
		AcdbKeyVector *v = (AcdbKeyVector *)kp;
		printf("CKV %u:", c);
		for (uint32_t k = 0; k < v->num_keys; k++) printf(" %08x=%08x", v->graph_key_vector[k].key, v->graph_key_vector[k].value);
		printf("\n");
		AcdbGraphKeyVector none = { 0, NULL };
		AcdbSgIdCalKeyVector q = { 1, &sg, none, { v->num_keys, v->graph_key_vector } };
		AcdbBlob b = { 0 };
		r = acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_NONPERSIST, &q, sizeof q, &b, sizeof b);
		if (!r && b.buf_size) {
			b.buf = malloc(b.buf_size);
			if (!acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_CALIBRATION_DATA_NONPERSIST, &q, sizeof q, &b, sizeof b)) {
				char tag[32]; snprintf(tag, sizeof tag, "np-ckv%u", c);
				dump_blob(tag, b.buf, b.buf_size, iid, c == 0 ? outdir : NULL);
			}
		} else printf("  nonpersist r=%d size %u\n", r, b.buf_size);
		kp += 4 + 8 * v->num_keys;
	}
	return 0;
}
