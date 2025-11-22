#ifndef CRYPTO_HASH_H_
#define CRYPTO_HASH_H_

#include <stdint.h>

/* Minimal public prototypes used by software/hash.c */
int crypto_cxof(unsigned char* out, unsigned long long outlen,
                const unsigned char* in, unsigned long long inlen,
                const unsigned char* cs, unsigned long long cslen);

int crypto_hash(unsigned char* out, const unsigned char* in,
                unsigned long long len);

/* Variant that allows selecting the Ascon-p rounds at runtime (6,8,12). */
int crypto_cxof_rounds(unsigned char* out, unsigned long long outlen,
                       const unsigned char* in, unsigned long long inlen,
                       const unsigned char* cs, unsigned long long cslen,
                       int pa_rounds);

/* Produce an output of exactly `outlen_bits` bits (packed MSB-first into bytes).
   `out` must have space for ceil(outlen_bits/8) bytes.
   A `_rounds` variant allows selecting the PA rounds at runtime (6/8/12).

    Note about customization length (`cslen`): the API accepts `cslen` as an
   unsigned long long, so in principle very large customization strings are
   supported. However the implementation multiplies `cslen * 8` and XORs the
   result into a 64-bit state word; extremely large `cslen` values will wrap
   modulo 2^64. For practical purposes, keep `cslen` small (for example <= 256
   bytes). This is a recommendation only — the function does not enforce this
   limit; applications should enforce any policy they need for resource and
   protocol constraints.
*/
int crypto_cxof_bits_rounds(unsigned char* out, unsigned long long outlen_bits,
                           const unsigned char* in, unsigned long long inlen,
                           const unsigned char* cs, unsigned long long cslen,
                           int pa_rounds);

/* Wrapper that uses the compile-time ASCON_PA_ROUNDS. */
int crypto_cxof_bits(unsigned char* out, unsigned long long outlen_bits,
                     const unsigned char* in, unsigned long long inlen,
                     const unsigned char* cs, unsigned long long cslen);

#endif /* CRYPTO_HASH_H_ */

/* Recommended maximum customization (label) length in bytes for safe operation.
   Use 256 bytes as a reasonable application-level limit; this is only
   guidance and not enforced by the library functions.

   Optional: define CXOF_WARN_ON_LONG_LABEL when compiling to emit a runtime
   warning (to stderr) if `cslen` exceeds 256 bytes. The warning is purely
   informational and does not change function behavior.
*/