SHELL:=/bin/bash

.PHONY: run build clean test format

run:
	zig build run -Doptimize=ReleaseFast

build:
	zig build -Doptimize=ReleaseFast

clean:
	rm -rf zig-cache

test:
	zig build test --summary all

format:
	zig fmt $$(find src -name "*.zig")
