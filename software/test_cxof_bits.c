/* test_cxof_bits.c
 * Simple CLI to exercise crypto_cxof_bits_rounds()
 * Usage: test_cxof_bits <message> <label> <out_bits> [pa_rounds]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "crypto_hash.h"

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s <message> <label> <out_bits> [pa_rounds]\n", prog);
    fprintf(stderr, "  pa_rounds is optional (6,8,12). Default: 12\n");
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        usage(argv[0]);
        return 2;
    }

    const unsigned char *msg = (const unsigned char *)argv[1];
    unsigned long long msglen = (unsigned long long)strlen((const char*)msg);
    const unsigned char *cs = (const unsigned char *)argv[2];
    unsigned long long cslen = (unsigned long long)strlen((const char*)cs);
    unsigned long long out_bits = strtoull(argv[3], NULL, 10);
    int pa_rounds = 12;
    if (argc >= 5) pa_rounds = atoi(argv[4]);

    unsigned long long out_bytes = (out_bits + 7) / 8;
    if (out_bytes == 0) {
        printf("Requested output length is 0 bits; nothing to do.\n");
        return 0;
    }

    unsigned char *out = malloc((size_t)out_bytes);
    if (!out) {
        perror("malloc");
        return 1;
    }
    memset(out, 0, (size_t)out_bytes);

    int rc = crypto_cxof_bits_rounds(out, out_bits, msg, msglen, cs, cslen, pa_rounds);
    if (rc) {
        fprintf(stderr, "crypto_cxof_bits_rounds returned %d\n", rc);
        free(out);
        return 1;
    }

    printf("message: '%s' (len=%llu)\n", (const char*)msg, msglen);
    printf("label:   '%s' (len=%llu)\n", (const char*)cs, cslen);
    printf("pa_rounds: %d\n", pa_rounds);
    printf("out_bits: %llu (bytes=%llu)\n", out_bits, out_bytes);

    /* print hex bytes: 16 bytes per line */
    printf("output (hex):\n");
    for (unsigned long long i = 0; i < out_bytes; ++i) {
        printf("%02x", out[i]);
        if (i + 1 == out_bytes) {
            printf("\n");
        } else if ((i % 16) == 15) {
            printf("\n");
        } else {
            printf(" ");
        }
    }

    /* print bits as MSB-first groups (space between bytes); final byte may be partial */
    unsigned int rem = (unsigned int)(out_bits & 7ULL);
    printf("bits:\n");
    for (unsigned long long i = 0; i < out_bytes; ++i) {
        unsigned char byte = out[i];
        if (i + 1 == out_bytes && rem) {
            /* print only the top `rem` bits of the last byte (MSB-first) */
            for (int b = 7; b >= 8 - (int)rem; --b) putchar(((byte >> b) & 1) ? '1' : '0');
        } else {
            for (int b = 7; b >= 0; --b) putchar(((byte >> b) & 1) ? '1' : '0');
        }
        if (i + 1 < out_bytes) {
            if ((i % 16) == 15) putchar('\n');
            else putchar(' ');
        }
    }
    if (out_bytes % 16 != 0) printf("\n");

    free(out);
    return 0;
}
