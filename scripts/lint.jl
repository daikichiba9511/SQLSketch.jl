#!/usr/bin/env julia

# JET static analysis script for SQLSketch.jl
#
# This script runs JET (Julia Error Tracer) to detect:
# - Type instabilities
# - Method errors
# - Undefined variables
# - Other static analysis issues
#
# Usage:
#   julia --project=. scripts/lint.jl

using JET

println("Running JET static analysis on SQLSketch...")
println("=" ^ 60)
println()

# Load the package first (required for JET v0.11+)
using SQLSketch

# Analyze the entire package
# JET v0.11: Use target_modules to focus on SQLSketch only (exclude dependencies)
report = report_package(SQLSketch;
                        toplevel_logger = nothing,
                        target_modules = (SQLSketch,))

# Filter out known false positives
function is_false_positive(r)
    # JET v0.11: MethodErrorReport for guarded code paths
    if r isa JET.MethodErrorReport
        err_msg = string(r)

        # False positive: compile_window_frame with Nothing
        # Code already has `if frame !== nothing` guard
        if contains(err_msg, "compile_window_frame") && contains(err_msg, "Nothing")
            return true
        end
    end

    return false
end

reports = filter(!is_false_positive, JET.get_reports(report))

# Print detailed report
if !isempty(reports)
    println()
    println("=" ^ 60)
    println("Detailed Report:")
    println("=" ^ 60)
    for (i, r) in enumerate(reports)
        println("\n[$i/$(length(reports))] ", r)
    end
end

println("\n" * "=" ^ 60)
println("Summary:")
println("  Total reports: $(length(reports))")
println("  (JET v0.11 with target_modules filter + false positive filtering)")

if isempty(reports)
    println("✓ No issues found!")
    exit(0)
else
    println("✗ Issues found - see details above")
    exit(1)
end
