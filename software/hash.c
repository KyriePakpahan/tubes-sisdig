#include "api.h"
#include "ascon.h"
#include "crypto_hash.h"
#include "permutations.h"
#include "printstate.h"
#include "word.h"
#include <stdio.h>

int crypto_cxof_rounds(unsigned char* out, unsigned long long outlen,
                       const unsigned char* in, unsigned long long inlen,
                       const unsigned char* cs, unsigned long long cslen,
                       int pa_rounds) {
  /* Optional runtime warning for long customization/label length. Enable by
     defining CXOF_WARN_ON_LONG_LABEL when building to print a debug warning
     if the customization string length exceeds 256 bytes. This does not
     prevent processing; it only logs a message to stderr. */
#ifdef CXOF_WARN_ON_LONG_LABEL
  if (cslen > 256ULL) {
    fprintf(stderr, "warning: customization label length %llu > 256 bytes; this is a recommendation only\n", (unsigned long long)cslen);
  }
#endif
  printbytes("z", cs, cslen);
  printbytes("m", in, inlen);
  /* initialize */
  ascon_state_t s;
  s.x[0] = ASCON_CXOF_IV;
  s.x[1] = 0;
  s.x[2] = 0;
  s.x[3] = 0;
  s.x[4] = 0;
  printstate("initial value", &s);
  P_rounds(&s, pa_rounds);
  printstate("initialization", &s);

  /* absorb customization length */
  s.x[0] ^= cslen * 8;
  printstate("absorb cs length", &s);
  P_rounds(&s, pa_rounds);

  /* absorb full customization blocks */
  while (cslen >= ASCON_HASH_RATE) {
    s.x[0] ^= LOADBYTES(cs, 8);
    printstate("absorb cs", &s);
    P_rounds(&s, pa_rounds);
    cs += ASCON_HASH_RATE;
    cslen -= ASCON_HASH_RATE;
  }
  /* absorb final customization block */
  s.x[0] ^= LOADBYTES(cs, cslen);
  s.x[0] ^= PAD(cslen);
  printstate("pad cs", &s);
  P_rounds(&s, pa_rounds);

  /* absorb full plaintext blocks */
  while (inlen >= ASCON_HASH_RATE) {
    s.x[0] ^= LOADBYTES(in, 8);
    printstate("absorb plaintext", &s);
    P_rounds(&s, pa_rounds);
    in += ASCON_HASH_RATE;
    inlen -= ASCON_HASH_RATE;
  }
  /* absorb final plaintext block */
  s.x[0] ^= LOADBYTES(in, inlen);
  s.x[0] ^= PAD(inlen);
  printstate("pad plaintext", &s);
  P_rounds(&s, pa_rounds);

  /* squeeze full output blocks */
  while (outlen > ASCON_HASH_RATE) {
    STOREBYTES(out, s.x[0], 8);
    printstate("squeeze output", &s);
    P_rounds(&s, pa_rounds);
    out += ASCON_HASH_RATE;
    outlen -= ASCON_HASH_RATE;
  }
  /* squeeze final output block */
  STOREBYTES(out, s.x[0], outlen);
  printstate("squeeze output", &s);
  printbytes("h", out + outlen - CRYPTO_BYTES, CRYPTO_BYTES);

  return 0;
}

int crypto_cxof(unsigned char* out, unsigned long long outlen,
                const unsigned char* in, unsigned long long inlen,
                const unsigned char* cs, unsigned long long cslen) {
  return crypto_cxof_rounds(out, outlen, in, inlen, cs, cslen, ASCON_PA_ROUNDS);
}

int crypto_cxof_bits_rounds(unsigned char* out, unsigned long long outlen_bits,
                           const unsigned char* in, unsigned long long inlen,
                           const unsigned char* cs, unsigned long long cslen,
                           int pa_rounds) {
  if (outlen_bits == 0) return 0;
  /* Optional runtime warning for long customization/label length (see above). */
#ifdef CXOF_WARN_ON_LONG_LABEL
  if (cslen > 256ULL) {
    fprintf(stderr, "warning: customization label length %llu > 256 bytes; this is a recommendation only\n", (unsigned long long)cslen);
  }
#endif
  unsigned long long outlen_bytes = (outlen_bits + 7) / 8ULL;
  int rc = crypto_cxof_rounds(out, outlen_bytes, in, inlen, cs, cslen, pa_rounds);
  if (rc != 0) return rc;
  /* If number of bits is not a multiple of 8, mask the last byte to keep top (MSB) bits. */
  unsigned int rem = outlen_bits & 7U; /* 0..7 */
  if (rem) {
    /* Keep top `rem` bits in the last byte (MSB-first). Create mask like 11100000 for rem=3 */
    unsigned char mask = (unsigned char)(0xFF & (~((1u << (8 - rem)) - 1)));
    out[outlen_bytes - 1] &= mask;
  }
  return 0;
}

int crypto_cxof_bits(unsigned char* out, unsigned long long outlen_bits,
                     const unsigned char* in, unsigned long long inlen,
                     const unsigned char* cs, unsigned long long cslen) {
  return crypto_cxof_bits_rounds(out, outlen_bits, in, inlen, cs, cslen, ASCON_PA_ROUNDS);
}

int crypto_hash(unsigned char* out, const unsigned char* in,
                unsigned long long len) {
  return crypto_cxof(out, CRYPTO_BYTES, in, len, (void*)0, 0);
}