.PHONY: help test lint format format-check clean all docs docs-open docs-url benchmark benchmark-pg benchmark-pg-basic benchmark-pg-types benchmark-pg-comparison benchmark-pg-overhead

# Default target
help:
	@echo "SQLSketch.jl - Available targets:"
	@echo ""
	@echo "  make test                  - Run all tests"
	@echo "  make lint                  - Run JET static analysis"
	@echo "  make format                - Format all Julia files (dev tool)"
	@echo "  make format-check          - Check if files are formatted (CI)"
	@echo "  make benchmark             - Run SQLite benchmarks"
	@echo "  make benchmark-pg          - Run all PostgreSQL benchmarks"
	@echo "  make benchmark-pg-basic    - Run PostgreSQL basic benchmarks"
	@echo "  make benchmark-pg-types    - Run PostgreSQL type benchmarks"
	@echo "  make benchmark-pg-comparison - Run SQLite vs PostgreSQL comparison"
	@echo "  make benchmark-pg-overhead - Run SQLSketch vs raw LibPQ overhead analysis"
	@echo "  make docs                  - Build documentation"
	@echo "  make docs-open             - Build and open documentation in browser"
	@echo "  make docs-url              - Show documentation URL"
	@echo "  make clean                 - Remove temporary files"
	@echo "  make all                   - Run lint and test"
	@echo ""

# Run tests
test:
	julia --project=. -e 'using Pkg; Pkg.test()'

# Run JET static analysis
lint:
	julia --project=. scripts/lint.jl

# Run SQLite benchmarks
benchmark:
	@echo "Running SQLite benchmarks..."
	julia --project=. bench/run_all.jl

# Run all PostgreSQL benchmarks
benchmark-pg: benchmark-pg-basic benchmark-pg-types benchmark-pg-comparison benchmark-pg-overhead
	@echo ""
	@echo "✓ All PostgreSQL benchmarks completed!"

# Run PostgreSQL basic benchmarks
benchmark-pg-basic:
	@echo "Running PostgreSQL basic benchmarks..."
	@echo "Note: Requires PostgreSQL server running on localhost:5432"
	@echo "Start with: docker run --name sqlsketch-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sqlsketch_bench -p 5432:5432 -d postgres:15"
	@echo ""
	julia --project=. bench/postgresql/basic.jl || (echo ""; echo "❌ PostgreSQL benchmarks failed. Is PostgreSQL running?"; echo "See bench/postgresql/README.md for setup instructions"; exit 1)

# Run PostgreSQL type benchmarks
benchmark-pg-types:
	@echo ""
	@echo "Running PostgreSQL type-specific benchmarks..."
	julia --project=. bench/postgresql/types.jl || (echo ""; echo "❌ PostgreSQL type benchmarks failed"; exit 1)

# Run SQLite vs PostgreSQL comparison
benchmark-pg-comparison:
	@echo ""
	@echo "Running SQLite vs PostgreSQL comparison..."
	julia --project=. bench/postgresql/comparison.jl || (echo ""; echo "❌ Comparison benchmarks failed"; exit 1)

# Run PostgreSQL overhead analysis (SQLSketch vs raw LibPQ)
benchmark-pg-overhead:
	@echo ""
	@echo "Running PostgreSQL overhead analysis..."
	julia --project=. bench/postgresql/overhead.jl || (echo ""; echo "❌ Overhead analysis failed"; exit 1)

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
