.PHONY: help test lint format format-check clean all docs docs-open docs-url benchmark

# Default target
help:
	@echo "SQLSketch.jl - Available targets:"
	@echo ""
	@echo "  make test          - Run all tests"
	@echo "  make lint          - Run JET static analysis"
	@echo "  make format        - Format all Julia files (dev tool)"
	@echo "  make format-check  - Check if files are formatted (CI)"
	@echo "  make benchmark     - Run performance benchmarks"
	@echo "  make docs          - Build documentation"
	@echo "  make docs-open     - Build and open documentation in browser"
	@echo "  make docs-url      - Show documentation URL"
	@echo "  make clean         - Remove temporary files"
	@echo "  make all           - Run lint and test"
	@echo ""

# Run tests
test:
	julia --project=. -e 'using Pkg; Pkg.test()'

# Run JET static analysis
lint:
	julia --project=. scripts/lint.jl

# Run benchmarks
benchmark:
	julia --project=. bench/run_all.jl

# Format all Julia files (using .tools environment)
format:
	julia --project=.tools .tools/format.jl

# Check formatting (for CI, using .tools environment)
format-check:
	julia --project=.tools -e 'using JuliaFormatter; exit(format("."; overwrite=false) ? 0 : 1)'

# Clean temporary files
clean:
	find . -type f -name "*.jl.cov" -delete
	find . -type f -name "*.jl.*.cov" -delete
	find . -type f -name "*.jl.mem" -delete
	rm -rf Manifest.toml.bak

# Build documentation
docs:
	@echo "Building documentation..."
	cd docs && julia --project=. make.jl
	@echo "✓ Documentation built successfully!"
	@echo "  Open: docs/build/index.html"

# Build and open documentation
docs-open: docs
	@echo "Opening documentation in browser..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		open docs/build/index.html; \
	elif [ "$$(uname)" = "Linux" ]; then \
		xdg-open docs/build/index.html; \
	else \
		echo "Please open docs/build/index.html manually"; \
	fi

# Show documentation URL
docs-url:
	@echo "Documentation location:"
	@echo "  file://$(shell pwd)/docs/build/index.html"
	@echo ""
	@echo "GitHub repository:"
	@echo "  https://github.com/daikichiba9511/SQLSketch.jl"

# Run all checks (lint, test)
all: lint test
	@echo ""
	@echo "✓ All checks passed!"
