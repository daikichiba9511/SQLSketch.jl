# SQLSketch.jl Documentation

This directory contains the documentation for SQLSketch.jl, built with [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl).

## Building the Documentation

### Prerequisites

The documentation dependencies are managed separately from the main project:

```bash
cd docs/
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Build HTML Documentation

```bash
julia --project=. make.jl
```

The generated HTML documentation will be in `docs/build/`.

### View Documentation

Open `docs/build/index.html` in your browser:

```bash
open docs/build/index.html  # macOS
xdg-open docs/build/index.html  # Linux
start docs/build/index.html  # Windows
```

## Documentation Structure

```
docs/
├── make.jl              # Documenter build script
├── Project.toml         # Documentation dependencies
├── Manifest.toml        # Locked dependency versions
├── src/                 # Documentation source files
│   ├── index.md         # Home page
│   ├── getting-started.md  # Getting started guide
│   ├── tutorial.md      # Step-by-step tutorial
│   ├── api.md           # API reference
│   └── design.md        # Design philosophy
└── build/               # Generated HTML (gitignored)
```

## Content Overview

- **index.md** - Home page with overview, quick example, and feature highlights
- **getting-started.md** - Installation, database setup, core concepts, common patterns
- **tutorial.md** - Complete blog application tutorial demonstrating all features
- **api.md** - API reference (auto-generated from docstrings)
- **design.md** - Design philosophy and architectural decisions

## Adding Documentation

### Add a New Page

1. Create a new `.md` file in `docs/src/`
2. Add it to the `pages` list in `docs/make.jl`:
   ```julia
   pages = [
       "Home" => "index.md",
       "Getting Started" => "getting-started.md",
       "Tutorial" => "tutorial.md",
       "API Reference" => "api.md",
       "Design" => "design.md",
       "Your New Page" => "new-page.md",  # Add here
   ]
   ```
3. Rebuild: `julia --project=. make.jl`

### Add Docstrings to API Reference

To document a function in the API reference:

1. Add a docstring to the function in the source code:
   ```julia
   """
       my_function(arg::Type) -> ReturnType

   Brief description of what this function does.

   # Arguments
   - `arg::Type`: Description of argument

   # Returns
   - `ReturnType`: Description of return value

   # Examples
   ```julia
   result = my_function(value)
   ```
   """
   function my_function(arg::Type)::ReturnType
       # implementation
   end
   ```

2. Add the function to `docs/src/api.md`:
   ```markdown
   ## Section Name

   ```@docs
   my_function
   ```
   ```

3. Rebuild documentation

## Deployment

### Local Preview

Build and view locally (see above).

### GitHub Pages (Future)

When ready to deploy to GitHub Pages:

1. Set up GitHub Pages in repository settings
2. Configure GitHub Actions workflow for automatic builds
3. Push to main branch - docs will auto-deploy

See [Documenter.jl documentation](https://documenter.juliadocs.org/stable/) for deployment details.

## Troubleshooting

### Error: "undefined binding 'function_name'"

The function either:
- Doesn't have a docstring
- Isn't exported from the module
- The name is misspelled in `api.md`

Fix: Add docstring to function and ensure it's exported.

### Error: "invalid local link"

Internal links must use relative paths and point to files in `docs/src/`.

Fix: Update links to use correct paths (e.g., `api.md` not `api-reference.md`).

### Build is slow

First build is slow due to precompilation. Subsequent builds are faster.

Use `checkdocs = :none` in `make.jl` during development to skip docstring checks.

## Style Guide

- Use clear, concise language
- Provide runnable code examples
- Show both simple and advanced usage
- Include error handling examples
- Follow existing structure and tone
