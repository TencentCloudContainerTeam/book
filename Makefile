# It's necessary to set this because some environments don't link sh -> bash.
SHELL          := /bin/bash


.PHONY: all
all: index

.PHONY: index
index:
	script/update-index.sh zh

.PHONY: build
build:
	hugo