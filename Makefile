.PHONY: help all test docs publish deploy-docs

# Extract version from mix.exs
VERSION := $(shell grep '@version "' mix.exs | cut -d '"' -f 2)

# Load environment variables from .env file if it exists
ifneq ("$(wildcard .env)","")
	include .env
	export $(shell sed 's/=.*//' .env)
endif

help:
	@echo "Available targets:"
	@echo "  test         - Run all tests"
	@echo "  docs         - Generate documentation"
	@echo "  publish      - Publish package to Hex.pm (requires HEX_API_KEY in .env)"
	@echo "  deploy-docs  - Build and publish documentation to GitHub Pages"

all: test docs

test:
	mix test

docs:
	mix docs

publish: test
	@echo "Publishing version $(VERSION) to Hex..."
	@echo "Ensure you have updated the version in mix.exs and CHANGELOG.md"
	@if [ -z "$(HEX_API_KEY)" ]; then echo "Error: HEX_API_KEY is not set. Please check your .env file."; exit 1; fi
	mix hex.publish --yes

deploy-docs: docs
	@echo "Deploying docs to gh-pages..."
	cd doc && \
	git init && \
	git checkout -b deploy && \
	git add . && \
	git commit -m "Deploy docs for version $(VERSION)" && \
	git push --force $$(git -C .. remote get-url origin) deploy:gh-pages
	@echo "Docs deployed!"