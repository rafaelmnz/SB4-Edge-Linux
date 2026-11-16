/* Dump every graph in an AudioReach ACDB: GKV -> subgraphs -> containers/modules (APM_PARAM_ID_MODULES_LIST). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "acdb.h"
#include "ar_osal_error.h"

static const struct { uint32_t id; const char *n; } names[] = {
	{0x070010a3,"FLUENCE_NN"},{0x070010d9,"FLUENCE_NN_NS"},{0x07001031,"SMECNS_V2"},{0x07001033,"FLUENCE_EF"},
	{0x0700103d,"FLUENCE_BS"},{0x07001034,"FLUENCE_PRO_VC"},{0x0700103e,"FLUENCE_PRO_VR"},{0x0700103f,"SM_FLUENCE_SB"},
	{0x07001040,"MM_FLUENCE_SB"},{0x0700102d,"FFECNS"},{0x0700105b,"CFCM"},{0x070010d8,"ANS"},{0,0}};
static const char *mname(uint32_t id) { for (int i = 0; names[i].n; i++) if (names[i].id == id) return names[i].n; return ""; }

static void dump_modules(const uint8_t *b, uint32_t sz)
{
	uint32_t o = 0;
	while (o + 16 <= sz) {
		uint32_t iid, pid, psz;
		memcpy(&iid, b + o, 4); memcpy(&pid, b + o + 4, 4); memcpy(&psz, b + o + 8, 4);
		const uint8_t *p = b + o + 16;
		if (pid == 0x08001002) {	/* MODULES_LIST: num_modules_list, {sg, cont, num, {mid, iid}*}* */
			uint32_t n, q = 4; memcpy(&n, p, 4);
			for (uint32_t i = 0; i < n && q + 12 <= psz; i++) {
				uint32_t sg, ct, nm; memcpy(&sg, p + q, 4); memcpy(&ct, p + q + 4, 4); memcpy(&nm, p + q + 8, 4); q += 12;
				printf("      container 0x%x (sg 0x%x):", ct, sg);
				for (uint32_t j = 0; j < nm && q + 8 <= psz; j++, q += 8) {
					uint32_t mid, mi; memcpy(&mid, p + q, 4); memcpy(&mi, p + q + 4, 4);
					printf(" 0x%08x/0x%x%s%s", mid, mi, *mname(mid) ? "=" : "", mname(mid));
				}
				printf("\n");
			}
		}
		o += 16 + ((psz + 7) & ~7u);
	}
}

int main(int argc, char **argv)
{
	AcdbDataFiles files = { .num_files = 1 };
	strncpy(files.acdbFiles[0].fileName, argv[1], MAX_FILENAME_LENGTH - 1);
	files.acdbFiles[0].fileNameLen = strlen(files.acdbFiles[0].fileName);
	if (acdb_init(&files, NULL)) { fprintf(stderr, "acdb_init failed\n"); return 1; }

	AcdbUintList keys = { 0, NULL };
	AcdbKeyVectorList kvl = { 0 };
	int32_t r = acdb_ioctl(ACDB_CMD_GET_SUPPORTED_GKVS, &keys, sizeof(keys), &kvl, sizeof(kvl));
	kvl.key_vector_list = malloc(kvl.list_size);
	r = acdb_ioctl(ACDB_CMD_GET_SUPPORTED_GKVS, &keys, sizeof(keys), &kvl, sizeof(kvl));
	printf("GKVs: %u (r=%d)\n", kvl.num_key_vectors, r);

	uint8_t *kp = (uint8_t *)kvl.key_vector_list;
	for (uint32_t g = 0; g < kvl.num_key_vectors; g++) {
		AcdbKeyVector *kv = (AcdbKeyVector *)kp;
		printf("GKV %u:", g);
		for (uint32_t k = 0; k < kv->num_keys; k++) printf(" %08x=%08x", kv->graph_key_vector[k].key, kv->graph_key_vector[k].value);
		printf("\n");
		AcdbGraphKeyVector gkv = { kv->num_keys, kv->graph_key_vector };
		AcdbGetGraphRsp gr = { 0 };
		if (acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &gr, sizeof(gr)) == 0 && gr.size) {
			gr.subgraphs = malloc(gr.size);
			acdb_ioctl(ACDB_CMD_GET_GRAPH, &gkv, sizeof(gkv), &gr, sizeof(gr));
			uint8_t *sp = (uint8_t *)gr.subgraphs;
			for (uint32_t s = 0; s < gr.num_subgraphs; s++) {
				AcdbSubgraph *sg = (AcdbSubgraph *)sp;
				uint32_t id = sg->sg_id;
				printf("    sg 0x%x\n", id);
				AcdbSgIdGraphKeyVector q = { 1, &id, gkv };
				AcdbGetSubgraphDataRsp sd = { 0 };
				if (acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_DATA, &q, sizeof(q), &sd, sizeof(sd)) == 0) {
					sd.driver_prop.sub_graph_prop_data = malloc(sd.driver_prop.size + 16);
					sd.spf_blob.buf = malloc(sd.spf_blob.buf_size + 16);
					if (acdb_ioctl(ACDB_CMD_GET_SUBGRAPH_DATA, &q, sizeof(q), &sd, sizeof(sd)) == 0)
						dump_modules(sd.spf_blob.buf, sd.spf_blob.buf_size);
				}
				sp += 8 + 4 * sg->num_dst_sgids;
			}
		}
		kp += 4 + 8 * kv->num_keys;
	}
	return 0;
}
