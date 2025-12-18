#include <stdio.h>
#include <string.h>
#include "api.h"
#include "crypto_hash.h"

int main() {
    unsigned char out[64];
    unsigned char in[] = "";
    unsigned char cs[] = "";
    
    // Test Case 1: Empty Z, Empty M.
    // crypto_cxof(out, outlen, in, inlen, cs, cslen)
    
    printf("Running Ascon CXOF128 Empty/Empty Test...\n");
    crypto_cxof(out, 64, in, 0, cs, 0);
    
    printf("Hash Output: ");
    for(int i=0; i<8; i++) printf("%02X", out[i]);
    printf("...\n");
    
    printf("Full Block: ");
    for(int i=0; i<8; i++) printf("%02X", out[i]);
    printf("\n");
    
    // Also print bytes to see endianness in memory
    printf("First Word Bytes: ");
    for(int i=0; i<8; i++) printf("%02X ", out[i]);
    printf("\n");

    return 0;
}
