BATS := ./test_helper/bats-core/bin/bats
BATS_FLAGS := --print-output-on-failure

.PHONY: all hook commands sync clean test-one

all: hook commands sync

hook:
	$(BATS) $(BATS_FLAGS) hooks/

commands:
	$(BATS) $(BATS_FLAGS) commands/

sync:
	$(BATS) $(BATS_FLAGS) sync_contract.bats

test-one:
	$(BATS) $(BATS_FLAGS) $(FILE)

clean:
	@echo "Nothing to clean (bats uses temp dirs)"
