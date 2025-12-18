/* test_cxof_bits_hex.c
 * CLI that accepts message/label as hex strings (possibly empty) and
 * produces the CXOF output as a single hex line. This makes automated
 * comparison against known test vectors easier.
 *
 * Usage: test_cxof_bits_hex <msg_hex> <label_hex> <out_bits> [pa_rounds]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include "crypto_hash.h"

static unsigned char hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return 0xFF;
}

/* decode a hex string (possibly empty) into bytes. Returns malloc'd buffer
 * and sets *outlen. Caller must free. On error returns NULL. Accepts
 * either even-length hex strings; odd length treated as if prefixed with 0.
 */
static unsigned char *decode_hex(const char *hex, size_t *outlen)
{
    size_t len = hex ? strlen(hex) : 0;
    if (!hex || len == 0) {
        *outlen = 0;
        return malloc(0);
    }
    size_t i = 0;
    /* skip optional 0x/0X */
    if (len >= 2 && hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        hex += 2;
        len -= 2;
    }
    /* remove any whitespace inside (be permissive) */
    char *tmp = malloc(len + 1);
    if (!tmp) return NULL;
    size_t p = 0;
    for (i = 0; i < len; ++i) {
        if (!isspace((unsigned char)hex[i])) tmp[p++] = hex[i];
    }
    tmp[p] = '\0';
    /* if odd, treat as leading zero */
    size_t hexlen = p;
    size_t bytelen = (hexlen + 1) / 2;
    unsigned char *out = malloc(bytelen);
    if (!out) { free(tmp); return NULL; }
    size_t hi = 0;
    size_t o = 0;
    if (hexlen % 2 == 1) {
        unsigned char v = hexval(tmp[0]);
        if (v == 0xFF) { free(tmp); free(out); return NULL; }
        out[o++] = v;
        hi = 1;
    }
    for (; hi < hexlen; hi += 2) {
        unsigned char a = hexval(tmp[hi]);
        unsigned char b = hexval(tmp[hi+1]);
        if (a == 0xFF || b == 0xFF) { free(tmp); free(out); return NULL; }
        out[o++] = (unsigned char)((a << 4) | b);
    }
    free(tmp);
    *outlen = bytelen;
    return out;
}

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s <msg_hex> <label_hex> <out_bits> [pa_rounds]\n", prog);
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s \"\" \"\" 512       # empty msg and label, 512-bit output\n", prog);
    fprintf(stderr, "  %s 00 1011 512 12            # msg 0x00, label 0x10 0x11, ...\n", prog);
}

int main(int argc, char **argv)
{
    if (argc < 4) { usage(argv[0]); return 2; }
    const char *msg_hex = argv[1];
    const char *label_hex = argv[2];
    unsigned long long out_bits = strtoull(argv[3], NULL, 10);
    int pa_rounds = 12;
    if (argc >= 5) pa_rounds = atoi(argv[4]);

    size_t msglen = 0, labellen = 0;
    unsigned char *msg = decode_hex(msg_hex, &msglen);
    unsigned char *label = decode_hex(label_hex, &labellen);
    if (!msg || !label) {
        fprintf(stderr, "Invalid hex input\n");
        free(msg); free(label);
        return 3;
    }

    size_t out_bytes = (size_t)((out_bits + 7) / 8);
    unsigned char *out = malloc(out_bytes);
    if (!out) { perror("malloc"); free(msg); free(label); return 4; }
    memset(out, 0, out_bytes);

    int rc = crypto_cxof_bits_rounds(out, out_bits, msg, (unsigned long long)msglen, label, (unsigned long long)labellen, pa_rounds);
    if (rc) {
        fprintf(stderr, "crypto_cxof_bits_rounds returned %d\n", rc);
        free(msg); free(label); free(out);
        return 5;
    }

    /* print single-line hex (uppercase to match vectors) */
    for (size_t i = 0; i < out_bytes; ++i) printf("%02X", out[i]);
    printf("\n");

    free(msg); free(label); free(out);
    return 0;
}
