"""
Fast Path Verification Benchmark

Verifies that the fast path (immediate acquisition) works correctly:
1. Fast Path 1: Reuse existing available connection
2. Fast Path 2: Create new connection (when under max_size)
3. Slow Path: Wait (spin then park)
"""

using SQLSketch.Core
using SQLSketch.Drivers: SQLiteDriver
using Statistics

println("="^80)
println("Fast Path Verification")
println("="^80)
println()

# ============================================================================
# Test 1: Fast Path - Reuse existing connections
# ============================================================================

println("Test 1: FAST PATH - Reuse existing connections")
println("-"^80)
println("Setup:")
println("  Pool: min=10, max=10 (all pre-created)")
println("  Threads: 5 (half of pool size)")
println("  Operations: 1000 per thread")
println("  Expected: Zero waits, all fast path")
println()

pool1 = ConnectionPool(SQLiteDriver(), ":memory:"; min_size = 10, max_size = 10)

start = time()
tasks = [@async begin
             for _ in 1:1000
                 conn = acquire(pool1; timeout = 30.0)
                 release(pool1, conn)
             end
         end for _ in 1:5]

for t in tasks
    wait(t)
end
elapsed = time() - start

metrics1 = get_metrics(pool1)
throughput1 = (5 * 1000) / elapsed

println("Results:")
println("  Time: $(round(elapsed, digits=2))s")
println("  Throughput: $(round(throughput1, digits=0)) ops/sec")
println("  Total acquires: $(metrics1.total_acquires)")
println("  Total waits: $(metrics1.total_waits)")
println("  Spin waits: $(metrics1.spin_waits)")
println("  Park waits: $(metrics1.park_waits)")

if metrics1.total_waits == 0 && metrics1.spin_waits == 0 && metrics1.park_waits == 0
    println("  ✅ SUCCESS: Pure fast path (reuse)")
else
    println("  ⚠️  WARNING: Unexpected waits detected")
end

close(pool1)
println()

# ============================================================================
# Test 2: Fast Path - Create new connections
# ============================================================================

println("Test 2: FAST PATH - Create new connections")
println("-"^80)
println("Setup:")
println("  Pool: min=1, max=20 (dynamic creation)")
println("  Threads: 10")
println("  Operations: 100 per thread")
println("  Expected: Some creation, minimal waits")
println()

pool2 = ConnectionPool(SQLiteDriver(), ":memory:"; min_size = 1, max_size = 20)

start = time()
tasks = [@async begin
             for _ in 1:100
                 conn = acquire(pool2; timeout = 30.0)
                 sleep(0.0001)  # Brief hold
                 release(pool2, conn)
             end
         end for _ in 1:10]

for t in tasks
    wait(t)
end
elapsed = time() - start

metrics2 = get_metrics(pool2)
throughput2 = (10 * 100) / elapsed

println("Results:")
println("  Time: $(round(elapsed, digits=2))s")
println("  Throughput: $(round(throughput2, digits=0)) ops/sec")
println("  Total acquires: $(metrics2.total_acquires)")
println("  Pool final size: $(metrics2.pool_size)")
println("  Total waits: $(metrics2.total_waits)")
println("  Spin waits: $(metrics2.spin_waits)")
println("  Park waits: $(metrics2.park_waits)")

wait_ratio = metrics2.total_waits / metrics2.total_acquires * 100
println("  Wait ratio: $(round(wait_ratio, digits=2))%")

if wait_ratio < 10.0
    println("  ✅ SUCCESS: Mostly fast path (dynamic creation)")
    println("             Waits only during pool growth")
else
    println("  ⚠️  WARNING: High wait ratio")
end

close(pool2)
println()

# ============================================================================
# Test 3: Slow Path - Forced waiting
# ============================================================================

println("Test 3: SLOW PATH - Forced waiting (spin + park)")
println("-"^80)
println("Setup:")
println("  Pool: min=1, max=1 (only 1 connection!)")
println("  Threads: 5")
println("  Operations: 20 per thread")
println("  Expected: High waits, both spin and park")
println()

pool3 = ConnectionPool(SQLiteDriver(), ":memory:"; min_size = 1, max_size = 1)

start = time()
tasks = [@async begin
             for _ in 1:20
                 conn = acquire(pool3; timeout = 30.0)
                 sleep(0.001)  # Hold for 1ms
                 release(pool3, conn)
             end
         end for _ in 1:5]

for t in tasks
    wait(t)
end
elapsed = time() - start

metrics3 = get_metrics(pool3)
throughput3 = (5 * 20) / elapsed

println("Results:")
println("  Time: $(round(elapsed, digits=2))s")
println("  Throughput: $(round(throughput3, digits=0)) ops/sec")
println("  Total acquires: $(metrics3.total_acquires)")
println("  Total waits: $(metrics3.total_waits)")
println("  Spin waits: $(metrics3.spin_waits)")
println("  Park waits: $(metrics3.park_waits)")

if metrics3.spin_waits > 0 && metrics3.park_waits > 0
    spin_ratio = metrics3.spin_waits / (metrics3.spin_waits + metrics3.park_waits) * 100
    println("  Spin ratio: $(round(spin_ratio, digits=1))%")
    println("  Park ratio: $(round(100 - spin_ratio, digits=1))%")
end

wait_ratio = metrics3.total_waits / metrics3.total_acquires * 100
println("  Wait ratio: $(round(wait_ratio, digits=1))%")

if metrics3.spin_waits >= 10 && metrics3.park_waits > 0
    println("  ✅ SUCCESS: Slow path working (spin → park)")
else
    println("  ⚠️  WARNING: Spin or park not triggered")
end

close(pool3)
println()

# ============================================================================
# Summary
# ============================================================================

println("="^80)
println("SUMMARY")
println("="^80)
println()

println("┌────────────────────────────┬─────────────┬─────────┬──────────┬──────────┐")
println("│ Test                       │ Throughput  │ Waits   │ Spin     │ Park     │")
println("├────────────────────────────┼─────────────┼─────────┼──────────┼──────────┤")
println("│ Fast Path (reuse)          │ $(lpad(round(Int, throughput1), 11)) │ $(lpad(metrics1.total_waits, 7)) │ $(lpad(metrics1.spin_waits, 8)) │ $(lpad(metrics1.park_waits, 8)) │")
println("│ Fast Path (dynamic create) │ $(lpad(round(Int, throughput2), 11)) │ $(lpad(metrics2.total_waits, 7)) │ $(lpad(metrics2.spin_waits, 8)) │ $(lpad(metrics2.park_waits, 8)) │")
println("│ Slow Path (spin+park)      │ $(lpad(round(Int, throughput3), 11)) │ $(lpad(metrics3.total_waits, 7)) │ $(lpad(metrics3.spin_waits, 8)) │ $(lpad(metrics3.park_waits, 8)) │")
println("└────────────────────────────┴─────────────┴─────────┴──────────┴──────────┘")
println()

println("Analysis:")
println()

println("✅ Fast Path 1 (Reuse):")
if metrics1.total_waits == 0
    println("   - Perfect! Zero waits detected")
    println("   - All $(metrics1.total_acquires) acquisitions used fast path")
    println("   - Throughput: $(round(Int, throughput1)) ops/sec")
else
    println("   - Unexpected: $(metrics1.total_waits) waits occurred")
end
println()

println("✅ Fast Path 2 (Dynamic Create):")
wait_pct = metrics2.total_waits / metrics2.total_acquires * 100
println("   - Pool grew from 1 to $(metrics2.pool_size) connections")
println("   - Wait ratio: $(round(wait_pct, digits=1))%")
println("   - Most acquisitions used fast path (create new)")
if metrics2.park_waits > 0
    println("   - Note: $(metrics2.park_waits) park waits during pool growth (expected)")
end
println()

println("⚠️  Slow Path (Spin → Park):")
println("   - Total waits: $(metrics3.total_waits) ($(round(metrics3.total_waits / metrics3.total_acquires * 100, digits=1))%)")
println("   - Spin waits: $(metrics3.spin_waits)")
println("   - Park waits: $(metrics3.park_waits)")
if metrics3.spin_waits > 0 && metrics3.park_waits > 0
    println("   - Spin-then-park pattern confirmed!")
    println("   - First 10 iterations spin, then park")
end
println()

println("="^80)
println("CONCLUSION")
println("="^80)
println()

all_pass = true

# Check Fast Path 1
if metrics1.total_waits == 0 && metrics1.spin_waits == 0 && metrics1.park_waits == 0
    println("✅ Fast Path 1 (Reuse): WORKING")
else
    println("❌ Fast Path 1 (Reuse): FAILED")
    all_pass = false
end

# Check Fast Path 2
if metrics2.total_waits / metrics2.total_acquires < 0.2  # Less than 20% waits
    println("✅ Fast Path 2 (Dynamic): WORKING")
else
    println("❌ Fast Path 2 (Dynamic): FAILED")
    all_pass = false
end

# Check Slow Path
if metrics3.spin_waits >= 10 && metrics3.park_waits > 0
    println("✅ Slow Path (Spin→Park): WORKING")
else
    println("❌ Slow Path (Spin→Park): FAILED")
    all_pass = false
end

println()
if all_pass
    println("🎉 ALL PATHS VERIFIED!")
    println("   - Fast path handles no-contention cases efficiently")
    println("   - Slow path (spin→park) handles contention correctly")
else
    println("⚠️  SOME PATHS FAILED - Review implementation")
end

println("="^80)
