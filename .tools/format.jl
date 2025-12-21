#!/usr/bin/env julia
# Format code and show which files were changed (ruff-style output)

using JuliaFormatter

println("Formatting Julia code...")

# Get all Julia files (excluding this script)
script_path = @__FILE__
files = String[]
for (root, dirs, filenames) in walkdir(".")
    # Skip hidden directories and build artifacts
    if any(startswith(basename(root), prefix) for prefix in [".", "build", "docs"])
        continue
    end
    for file in filenames
        if endswith(file, ".jl")
            full_path = abspath(joinpath(root, file))
            # Skip this script itself
            if full_path != abspath(script_path)
                push!(files, joinpath(root, file))
            end
        end
    end
end

# Format each file and track changes
formatted_files = String[]
failed_files = String[]

for file in files
    # Check if file needs formatting (dry-run)
    needs_format = !format(file; overwrite = false)

    if needs_format
        # Actually format the file
        success = format(file; overwrite = true)
        if success
            push!(formatted_files, file)
        else
            push!(failed_files, file)
        end
    end
end

# Display results (ruff-style)
println()
if !isempty(formatted_files)
    println("$(length(formatted_files)) file(s) reformatted:")
    for file in formatted_files
        # Show relative path with green checkmark
        rel_path = relpath(file, ".")
        println("  ✓ $rel_path")
    end
end

if !isempty(failed_files)
    println()
    println("$(length(failed_files)) file(s) failed to format:")
    for file in failed_files
        rel_path = relpath(file, ".")
        println("  ✗ $rel_path")
    end
end

if isempty(formatted_files) && isempty(failed_files)
    println("No files reformatted")
end

# Summary
println()
total_files = length(files)
if isempty(failed_files)
    println("✓ $(total_files) files checked, $(length(formatted_files)) reformatted")
    exit(0)
else
    println("⚠ $(length(failed_files)) files failed to format")
    exit(1)
end
