CC := gcc
CFLAGS := -I. -Wall -Wextra -O2
TARGET := test_hash

SRCS := $(filter-out $(TARGET).c,$(wildcard *.c)) $(TARGET).c
OBJS := $(SRCS:.c=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: test-rounds
test-rounds: hash.o printstate.o
	$(CC) $(CFLAGS) -o test_rounds hash.o printstate.o test_rounds.c

.PHONY: test-cxof-bits
test-cxof-bits: hash.o printstate.o
	$(CC) $(CFLAGS) -o test_cxof_bits hash.o printstate.o test_cxof_bits.c
