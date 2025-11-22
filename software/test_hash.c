#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "crypto_hash.h"
#include "api.h"

int main(void) {
  const unsigned char msg[] = "abc";
  unsigned char out[CRYPTO_BYTES];

  if (crypto_hash(out, msg, strlen((const char*)msg)) != 0) {
    fprintf(stderr, "crypto_hash failed\n");
    return 1;
  }

  printf("crypto_hash output (%d bytes):\n", CRYPTO_BYTES);
  for (int i = 0; i < CRYPTO_BYTES; ++i) {
    printf("%02x", out[i]);
    if ((i & 15) == 15) printf("\n");
    else if (i != CRYPTO_BYTES - 1) printf(" ");
  }
  if (CRYPTO_BYTES % 16) printf("\n");
  return 0;
}
