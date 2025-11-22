# Software (Ascon) — build & test

This folder contains a small C implementation of Ascon CXOF/hash primitives and a few test runners used during development.

Quick build

From the repository root you can build only the software tests (this avoids invoking the VHDL flow):

```bash
make -C software test-cxof-bits
```

Available Make targets
- `test-cxof-bits` — builds `test_cxof_bits` CLI runner
- `test-rounds` — builds `test_rounds` (compare outputs for 6/8/12 rounds)

Running the CXOF runner

Usage:
```bash
./software/test_cxof_bits <message> <label> <out_bits> [pa_rounds]
# example: produce 255 bits using PA rounds = 12
./software/test_cxof_bits "hello" "team2" 255 12
```

Output format
- Hex bytes printed 16 bytes per line.
- A `bits:` line prints MSB-first bit groups for each byte; the final group may be a partial byte (if `out_bits` is not a multiple of 8).

Notes
- The top-level Makefile may run VHDL tooling; use `make -C software` to avoid that when you only need C utilities.
- The customization (`label`) length is accepted as an unsigned long long in the API; for practical use keep labels reasonably small (e.g. <= 256 bytes). The library does not enforce this limit but a runtime warning macro can be enabled at compile time.
- If you want to exclude build artefacts from commits, add a `.gitignore` with entries like `*.o`, `test_*`, and `cxof_out.txt`.

Want improvements?
- I can add file/stdin input modes, hex label parsing, or add tests asserting known vectors — tell me what you prefer.
