.PHONY: help test lint format format-check clean all

# Default target
help:
	@echo "SQLSketch.jl - Available targets:"
	@echo ""
	@echo "  make test          - Run all tests"
	@echo "  make lint          - Run JET static analysis"
	@echo "  make format        - Format all Julia files"
	@echo "  make format-check  - Check if files are formatted (CI)"
	@echo "  make clean         - Remove temporary files"
	@echo "  make all           - Run format, lint, and test"
	@echo ""

# Run tests
test:
	julia --project=. -e 'using Pkg; Pkg.test()'

# Run JET static analysis
lint:
	julia --project=. scripts/lint.jl

# Format all Julia files
format:
	julia --project=. -e 'using JuliaFormatter; format(".")'

# Check formatting (for CI)
format-check:
	julia --project=. -e 'using JuliaFormatter; exit(format("."; overwrite=false) ? 0 : 1)'

# Clean temporary files
clean:
	find . -type f -name "*.jl.cov" -delete
	find . -type f -name "*.jl.*.cov" -delete
	find . -type f -name "*.jl.mem" -delete
	rm -rf Manifest.toml.bak

# Run all checks (format, lint, test)
all: format lint test
	@echo ""
	@echo "✓ All checks passed!"
