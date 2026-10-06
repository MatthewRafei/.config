# make && make install   ->  ~/.local/bin/brightglide
CFLAGS ?= -O2 -Wall -Wextra

brightglide: brightglide.c
	$(CC) $(CFLAGS) -o $@ brightglide.c -lm

install: brightglide
	install -m 755 brightglide $(HOME)/.local/bin/brightglide

clean:
	rm -f brightglide

.PHONY: install clean
