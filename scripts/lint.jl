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

# Analyze the entire package
report = report_package("SQLSketch"; toplevel_logger = nothing)

# Filter out known false positives
# JET has trouble tracking symbols across module boundaries with include()
function is_false_positive(r)
    # Filter out module import false positives in Drivers module
    if r isa JET.ActualErrorWrapped
        err_msg = string(r.err)
        # Known false positives: Driver, Connection, connect, execute imports
        if contains(err_msg, "Drivers") &&
           (contains(err_msg, "Driver") ||
            contains(err_msg, "Connection") ||
            contains(err_msg, "connect") || contains(err_msg, "execute"))
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
println("  (Filtered out known false positives in Drivers module)")

if isempty(reports)
    println("✓ No issues found!")
    exit(0)
else
    println("✗ Issues found - see details above")
    exit(1)
end
