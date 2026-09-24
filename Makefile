NVIM ?= nvim

.PHONY: test bench spike

test:
	$(NVIM) --headless --clean -l tests/run.lua "$(FILTER)"

bench:
	$(NVIM) --headless --clean -l bench/bench.lua

spike:
	$(NVIM) --headless --clean -l spike/core_spike.lua
