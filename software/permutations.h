#ifndef PERMUTATIONS_H_
#define PERMUTATIONS_H_

#include <stdint.h>

#include "ascon.h"
#include "constants.h"
#include "printstate.h"
#include "round.h"

static inline void P12(ascon_state_t* s) {
  ROUND(s, 0xf0);
  ROUND(s, 0xe1);
  ROUND(s, 0xd2);
  ROUND(s, 0xc3);
  ROUND(s, 0xb4);
  ROUND(s, 0xa5);
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

static inline void P8(ascon_state_t* s) {
  ROUND(s, 0xb4);
  ROUND(s, 0xa5);
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

static inline void P6(ascon_state_t* s) {
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

/* Generic P permutation selector: compile-time dispatch to the PA rounds count.
   ASCON_PA_ROUNDS is defined in constants.h (usually 12). */
#if ASCON_PA_ROUNDS == 12
static inline void P(ascon_state_t* s) { P12(s); }
#elif ASCON_PA_ROUNDS == 8
static inline void P(ascon_state_t* s) { P8(s); }
#elif ASCON_PA_ROUNDS == 6
static inline void P(ascon_state_t* s) { P6(s); }
#else
/* Fallback: call P12 by default if an unexpected value is set. */
static inline void P(ascon_state_t* s) { P12(s); }
#endif

/* Runtime-selectable permutation wrapper: call P12/P8/P6 depending on pa_rounds. */
static inline void P_rounds(ascon_state_t* s, int pa_rounds) {
  switch (pa_rounds) {
    case 6:
      P6(s);
      break;
    case 8:
      P8(s);
      break;
    case 12:
    default:
      P12(s);
      break;
  }
}

#endif /* PERMUTATIONS_H_ */
#ifndef PERMUTATIONS_H_
#define PERMUTATIONS_H_

#include <stdint.h>

#include "ascon.h"
#include "constants.h"
#include "printstate.h"
#include "round.h"

static inline void P12(ascon_state_t* s) {
  ROUND(s, 0xf0);
  ROUND(s, 0xe1);
  ROUND(s, 0xd2);
  ROUND(s, 0xc3);
  ROUND(s, 0xb4);
  ROUND(s, 0xa5);
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

static inline void P8(ascon_state_t* s) {
  ROUND(s, 0xb4);
  ROUND(s, 0xa5);
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

static inline void P6(ascon_state_t* s) {
  ROUND(s, 0x96);
  ROUND(s, 0x87);
  ROUND(s, 0x78);
  ROUND(s, 0x69);
  ROUND(s, 0x5a);
  ROUND(s, 0x4b);
}

#endif /* PERMUTATIONS_H_ */