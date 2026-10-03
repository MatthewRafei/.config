# make && make install   ->  ~/.local/bin/nightlightd
PROTO = wlr-gamma-control-unstable-v1
CFLAGS ?= -O2 -Wall -Wextra

nightlightd: nightlightd.c $(PROTO)-protocol.c $(PROTO)-client-protocol.h
	$(CC) $(CFLAGS) -o $@ nightlightd.c $(PROTO)-protocol.c $$(pkg-config --cflags --libs wayland-client) -lm

$(PROTO)-client-protocol.h: $(PROTO).xml
	wayland-scanner client-header $< $@

$(PROTO)-protocol.c: $(PROTO).xml
	wayland-scanner private-code $< $@

install: nightlightd
	install -m 755 nightlightd $(HOME)/.local/bin/nightlightd

clean:
	rm -f nightlightd $(PROTO)-protocol.c $(PROTO)-client-protocol.h

.PHONY: install clean
