#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "crypto_hash.h"
#include "api.h"

static void print_hex(const unsigned char* b, size_t n) {
  for (size_t i = 0; i < n; ++i) {
    printf("%02x", b[i]);
    if ((i & 15) == 15) printf("\n");
    else if (i != n - 1) printf(" ");
  }
  if (n % 16) printf("\n");
}

int main(void) {
  const unsigned char msg[] = "abc";
  const unsigned long long outlen = 32; /* bytes to request */
  unsigned char out6[32], out8[32], out12[32];

  if (crypto_cxof_rounds(out6, outlen, msg, strlen((const char*)msg), NULL, 0, 6) != 0) {
    fprintf(stderr, "crypto_cxof_rounds(6) failed\n");
    return 1;
  }
  if (crypto_cxof_rounds(out8, outlen, msg, strlen((const char*)msg), NULL, 0, 8) != 0) {
    fprintf(stderr, "crypto_cxof_rounds(8) failed\n");
    return 1;
  }
  if (crypto_cxof_rounds(out12, outlen, msg, strlen((const char*)msg), NULL, 0, 12) != 0) {
    fprintf(stderr, "crypto_cxof_rounds(12) failed\n");
    return 1;
  }

  printf("Output (32 bytes) for rounds=6:\n");
  print_hex(out6, outlen);
  printf("Output (32 bytes) for rounds=8:\n");
  print_hex(out8, outlen);
  printf("Output (32 bytes) for rounds=12:\n");
  print_hex(out12, outlen);

  int eq6_8 = memcmp(out6, out8, outlen) == 0;
  int eq8_12 = memcmp(out8, out12, outlen) == 0;
  int eq6_12 = memcmp(out6, out12, outlen) == 0;

  printf("Comparisons:\n");
  printf(" rounds 6 == 8 ? %s\n", eq6_8 ? "YES" : "NO");
  printf(" rounds 8 == 12 ? %s\n", eq8_12 ? "YES" : "NO");
  printf(" rounds 6 == 12 ? %s\n", eq6_12 ? "YES" : "NO");

  return 0;
}
