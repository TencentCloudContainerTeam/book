# It's necessary to set this because some environments don't link sh -> bash.
SHELL          := /bin/bash


.PHONY: all
all: index

.PHONY: index
index:
	script/update-index.sh

.PHONY: build
build:
	hugo