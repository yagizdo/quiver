.PHONY: test test-hook test-commands test-sync setup-tests test-one

test:
	$(MAKE) -C tests all

test-hook:
	$(MAKE) -C tests hook

test-commands:
	$(MAKE) -C tests commands

test-sync:
	$(MAKE) -C tests sync

test-one:
	$(MAKE) -C tests test-one FILE=$(patsubst tests/%,%,$(FILE))

setup-tests:
	git submodule update --init --recursive
