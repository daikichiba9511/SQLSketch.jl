"""
Spin vs Park Performance Comparison

Compares performance when:
1. Spin-only: Low contention, resolved within 10 spins
2. Park-reaching: High contention, reaches park phase
"""

using SQLSketch.Core
using SQLSketch.Drivers: SQLiteDriver
using Statistics

println("="^80)
println("Spin vs Park Performance Comparison")
println("="^80)
println()

# ============================================================================
# Scenario 1: Spin-only (Low Contention)
# ============================================================================

println("Scenario 1: LOW CONTENTION (Spin-only)")
println("-"^80)
println("Configuration:")
println("  Pool size: 5")
println("  Threads: 10 (less than pool size)")
println("  Operations per thread: 100")
println("  Work duration: 0.0001s (very brief)")
println("  Expected: Most waits resolved in spin phase")
println()

function benchmark_low_contention(num_runs = 3)
    results = []

    for run in 1:num_runs
        pool = ConnectionPool(SQLiteDriver(), ":memory:"; min_size = 3, max_size = 5)

        start_time = time()

        # Low contention: 10 threads, 5 connections
        # Most operations won't need to wait, and when they do, spin resolves quickly
        tasks = [@async begin
                     for _ in 1:100
                         conn = acquire(pool; timeout = 30.0)
                         sleep(0.0001)  # Very brief work
                         release(pool, conn)
                     end
                 end for _ in 1:10]

        for t in tasks
            wait(t)
        end

        elapsed = time() - start_time
        total_ops = 10 * 100
        throughput = total_ops / elapsed

        metrics = get_metrics(pool)

        push!(results, (
            elapsed = elapsed,
            throughput = throughput,
            metrics = metrics
        ))

        println("  Run $run:")
        println("    Time: $(round(elapsed, digits=2))s")
        println("    Throughput: $(round(throughput, digits=0)) ops/sec")
        println("    Total waits: $(metrics.total_waits)")
        println("    Spin waits: $(metrics.spin_waits)")
        println("    Park waits: $(metrics.park_waits)")
        if metrics.spin_waits + metrics.park_waits > 0
            spin_ratio = metrics.spin_waits / (metrics.spin_waits + metrics.park_waits) * 100
            println("    Spin ratio: $(round(spin_ratio, digits=1))%")
        end

        close(pool)
    end

    return results
end

low_results = benchmark_low_contention()

println()
println("Summary (Low Contention):")
avg_throughput = mean(r.throughput for r in low_results)
avg_spin = mean(r.metrics.spin_waits for r in low_results)
avg_park = mean(r.metrics.park_waits for r in low_results)
println("  Average throughput: $(round(avg_throughput, digits=0)) ops/sec")
println("  Average spin waits: $(round(avg_spin, digits=0))")
println("  Average park waits: $(round(avg_park, digits=0))")
println()

# ============================================================================
# Scenario 2: Park-reaching (High Contention)
# ============================================================================

println("="^80)
println("Scenario 2: HIGH CONTENTION (Park-reaching)")
println("-"^80)
println("Configuration:")
println("  Pool size: 2 (small!)")
println("  Threads: 20 (much more than pool size)")
println("  Operations per thread: 50")
println("  Work duration: 0.001s (longer)")
println("  Expected: Many waits reach park phase")
println()

function benchmark_high_contention(num_runs = 3)
    results = []

    for run in 1:num_runs
        pool = ConnectionPool(SQLiteDriver(), ":memory:"; min_size = 1, max_size = 2)

        start_time = time()

        # High contention: 20 threads, only 2 connections
        # Many operations will wait long enough to reach park phase
        tasks = [@async begin
                     for _ in 1:50
                         conn = acquire(pool; timeout = 30.0)
                         sleep(0.001)  # Longer work = more contention
                         release(pool, conn)
                     end
                 end for _ in 1:20]

        for t in tasks
            wait(t)
        end

        elapsed = time() - start_time
        total_ops = 20 * 50
        throughput = total_ops / elapsed

        metrics = get_metrics(pool)

        push!(results, (
            elapsed = elapsed,
            throughput = throughput,
            metrics = metrics
        ))

        println("  Run $run:")
        println("    Time: $(round(elapsed, digits=2))s")
        println("    Throughput: $(round(throughput, digits=0)) ops/sec")
        println("    Total waits: $(metrics.total_waits)")
        println("    Spin waits: $(metrics.spin_waits)")
        println("    Park waits: $(metrics.park_waits)")
        if metrics.spin_waits + metrics.park_waits > 0
            spin_ratio = metrics.spin_waits / (metrics.spin_waits + metrics.park_waits) * 100
            park_ratio = metrics.park_waits / (metrics.spin_waits + metrics.park_waits) * 100
            println("    Spin ratio: $(round(spin_ratio, digits=1))%")
            println("    Park ratio: $(round(park_ratio, digits=1))%")
        end
        if metrics.total_waits > 0
            avg_wait_time = metrics.avg_wait_time_ms
            println("    Avg wait time: $(round(avg_wait_time, digits=1))ms")
        end

        close(pool)
    end

    return results
end

high_results = benchmark_high_contention()

println()
println("Summary (High Contention):")
avg_throughput = mean(r.throughput for r in high_results)
avg_spin = mean(r.metrics.spin_waits for r in high_results)
avg_park = mean(r.metrics.park_waits for r in high_results)
avg_total_waits = mean(r.metrics.total_waits for r in high_results)
println("  Average throughput: $(round(avg_throughput, digits=0)) ops/sec")
println("  Average total waits: $(round(avg_total_waits, digits=0))")
println("  Average spin waits: $(round(avg_spin, digits=0))")
println("  Average park waits: $(round(avg_park, digits=0))")
println()

# ============================================================================
# Comparison
# ============================================================================

println("="^80)
println("COMPARISON")
println("="^80)
println()

low_throughput = mean(r.throughput for r in low_results)
high_throughput = mean(r.throughput for r in high_results)

low_spin = mean(r.metrics.spin_waits for r in low_results)
low_park = mean(r.metrics.park_waits for r in low_results)

high_spin = mean(r.metrics.spin_waits for r in high_results)
high_park = mean(r.metrics.park_waits for r in high_results)

println("┌─────────────────────────┬──────────────────┬──────────────────┐")
println("│ Metric                  │ Low Contention   │ High Contention  │")
println("├─────────────────────────┼──────────────────┼──────────────────┤")
println("│ Throughput (ops/sec)    │ $(lpad(round(Int, low_throughput), 16)) │ $(lpad(round(Int, high_throughput), 16)) │")
println("│ Spin waits              │ $(lpad(round(Int, low_spin), 16)) │ $(lpad(round(Int, high_spin), 16)) │")
println("│ Park waits              │ $(lpad(round(Int, low_park), 16)) │ $(lpad(round(Int, high_park), 16)) │")

if low_spin + low_park > 0
    low_spin_pct = round(low_spin / (low_spin + low_park) * 100, digits=1)
    if high_spin + high_park > 0
        high_spin_pct = round(high_spin / (high_spin + high_park) * 100, digits=1)
        println("│ Spin %                  │ $(lpad(low_spin_pct, 15))% │ $(lpad(high_spin_pct, 15))% │")
    else
        println("│ Spin %                  │ $(lpad(low_spin_pct, 15))% │ $(lpad("N/A", 16)) │")
    end
else
    if high_spin + high_park > 0
        high_spin_pct = round(high_spin / (high_spin + high_park) * 100, digits=1)
        println("│ Spin %                  │ $(lpad("N/A", 16)) │ $(lpad(high_spin_pct, 15))% │")
    else
        println("│ Spin %                  │ $(lpad("N/A", 16)) │ $(lpad("N/A", 16)) │")
    end
end

println("└─────────────────────────┴──────────────────┴──────────────────┘")
println()

# ============================================================================
# Analysis
# ============================================================================

println("ANALYSIS")
println("-"^80)
println()

println("✅ Low Contention (Spin-only):")
println("   - Pool has enough capacity (5 connections for 10 threads)")
println("   - Brief work duration (0.1ms) means connections released quickly")
println("   - Most waits (if any) resolved in spin phase")
if low_spin + low_park > 0
    println("   - Spin-to-park ratio: $(round(low_spin / max(low_park, 1), digits=1)):1")
end
println("   - Throughput: $(round(Int, low_throughput)) ops/sec")
println()

println("⚠️  High Contention (Park-reaching):")
println("   - Pool is small (only 2 connections for 20 threads)")
println("   - Longer work duration (1ms) means connections held longer")
println("   - Many threads waiting → spin phase insufficient → park phase entered")
if high_spin + high_park > 0
    println("   - Spin-to-park ratio: $(round(high_spin / max(high_park, 1), digits=1)):1")
end
println("   - Throughput: $(round(Int, high_throughput)) ops/sec")
println()

throughput_ratio = low_throughput / high_throughput
println("📊 Throughput Comparison:")
println("   - Low contention is $(round(throughput_ratio, digits=2))x faster")
println("   - This is expected: less contention = less waiting")
println()

println("🎯 Key Insight:")
println("   - Spin phase handles low contention efficiently (fast path)")
println("   - Park phase handles high contention gracefully (CPU-efficient)")
if high_park > high_spin
    println("   - High contention scenario shows park phase is working correctly!")
    println("   - notify() is being used to wake parked threads")
end
println()

println("="^80)
