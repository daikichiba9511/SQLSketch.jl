"""
# Window Function Tests

Unit tests for window function AST construction and SQL compilation.

These tests verify:
- Window function expression construction
- OVER clause with PARTITION BY and ORDER BY
- Window frame specifications (ROWS, RANGE, GROUPS)
- SQL generation for various window functions
- Ranking functions (ROW_NUMBER, RANK, DENSE_RANK, NTILE)
- Value functions (LAG, LEAD, FIRST_VALUE, LAST_VALUE, NTH_VALUE)
- Aggregate window functions (SUM, AVG, MIN, MAX, COUNT)
"""

using Test
using SQLSketch
using SQLSketch.Core

@testset "Window Functions" begin
    @testset "WindowFrame Construction" begin
        # ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        frame1 = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)
        @test frame1.mode == :ROWS
        @test frame1.start_bound == :UNBOUNDED_PRECEDING
        @test frame1.end_bound == :CURRENT_ROW

        # ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        frame2 = window_frame(:ROWS, -1, 1)
        @test frame2.mode == :ROWS
        @test frame2.start_bound == -1
        @test frame2.end_bound == 1

        # RANGE UNBOUNDED PRECEDING (single bound)
        frame3 = window_frame(:RANGE, :UNBOUNDED_PRECEDING)
        @test frame3.mode == :RANGE
        @test frame3.start_bound == :UNBOUNDED_PRECEDING
        @test frame3.end_bound === nothing
    end

    @testset "Over Clause Construction" begin
        # Empty OVER clause
        over1 = over()
        @test isempty(over1.partition_by)
        @test isempty(over1.order_by)
        @test over1.frame === nothing

        # PARTITION BY only
        over2 = over(partition_by = [col(:emp, :dept)])
        @test length(over2.partition_by) == 1
        @test isequal(over2.partition_by[1], col(:emp, :dept))
        @test isempty(over2.order_by)

        # ORDER BY only
        over3 = over(order_by = [(col(:emp, :salary), true)])
        @test isempty(over3.partition_by)
        @test length(over3.order_by) == 1
        @test isequal(over3.order_by[1], (col(:emp, :salary), true))

        # PARTITION BY + ORDER BY + FRAME
        frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)
        over4 = over(partition_by = [col(:emp, :dept)],
                     order_by = [(col(:emp, :salary), true)],
                     frame = frame)
        @test length(over4.partition_by) == 1
        @test length(over4.order_by) == 1
        @test over4.frame === frame
    end

    @testset "Ranking Functions" begin
        # ROW_NUMBER()
        rn = row_number(over(partition_by = [col(:emp, :dept)],
                             order_by = [(col(:emp, :salary), true)]))
        @test rn.name == :ROW_NUMBER
        @test isempty(rn.args)
        @test length(rn.over.partition_by) == 1

        # RANK()
        r = rank(over(order_by = [(col(:emp, :salary), true)]))
        @test r.name == :RANK
        @test isempty(r.args)

        # DENSE_RANK()
        dr = dense_rank(over(order_by = [(col(:emp, :salary), true)]))
        @test dr.name == :DENSE_RANK
        @test isempty(dr.args)

        # NTILE(4)
        nt = ntile(4, over(order_by = [(col(:emp, :salary), true)]))
        @test nt.name == :NTILE
        @test length(nt.args) == 1
        @test isequal(nt.args[1], literal(4))
    end

    @testset "Value Functions" begin
        # LAG(price)
        lag1 = lag(col(:prices, :price),
                   over(order_by = [(col(:prices, :date), false)]))
        @test lag1.name == :LAG
        @test length(lag1.args) == 2
        @test isequal(lag1.args[1], col(:prices, :price))
        @test isequal(lag1.args[2], literal(1))

        # LAG(price, 3, 0)
        lag2 = lag(col(:prices, :price),
                   over(order_by = [(col(:prices, :date), false)]),
                   3, literal(0))
        @test length(lag2.args) == 3
        @test isequal(lag2.args[2], literal(3))
        @test isequal(lag2.args[3], literal(0))

        # LEAD(price)
        lead1 = lead(col(:prices, :price),
                     over(order_by = [(col(:prices, :date), false)]))
        @test lead1.name == :LEAD
        @test length(lead1.args) == 2

        # FIRST_VALUE(salary)
        fv = first_value(col(:emp, :salary),
                         over(partition_by = [col(:emp, :dept)],
                              order_by = [(col(:emp, :hire_date), false)]))
        @test fv.name == :FIRST_VALUE
        @test length(fv.args) == 1
        @test isequal(fv.args[1], col(:emp, :salary))

        # LAST_VALUE(salary)
        lv = last_value(col(:emp, :salary),
                        over(partition_by = [col(:emp, :dept)],
                             order_by = [(col(:emp, :hire_date), false)]))
        @test lv.name == :LAST_VALUE

        # NTH_VALUE(salary, 2)
        nv = nth_value(col(:emp, :salary), 2,
                       over(partition_by = [col(:emp, :dept)],
                            order_by = [(col(:emp, :salary), true)]))
        @test nv.name == :NTH_VALUE
        @test length(nv.args) == 2
        @test isequal(nv.args[2], literal(2))
    end

    @testset "Aggregate Window Functions" begin
        # SUM
        ws = win_sum(col(:sales, :amount),
                     over(order_by = [(col(:sales, :date), false)],
                          frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)))
        @test ws.name == :SUM
        @test length(ws.args) == 1
        @test isequal(ws.args[1], col(:sales, :amount))

        # AVG
        wa = win_avg(col(:prices, :close),
                     over(order_by = [(col(:prices, :date), false)],
                          frame = window_frame(:ROWS, -29, :CURRENT_ROW)))
        @test wa.name == :AVG

        # MIN
        wmin = win_min(col(:data, :value), over())
        @test wmin.name == :MIN

        # MAX
        wmax = win_max(col(:data, :value), over())
        @test wmax.name == :MAX

        # COUNT
        wc = win_count(col(:events, :id), over())
        @test wc.name == :COUNT
    end

    @testset "Window Function SQL Compilation - Basic" begin
        dialect = SQLiteDialect()

        # ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC)
        wf1 = row_number(over(partition_by = [col(:emp, :department)],
                              order_by = [(col(:emp, :salary), true)]))
        params1 = Symbol[]
        sql1 = compile_expr(dialect, wf1, params1)
        @test sql1 ==
              "ROW_NUMBER() OVER (PARTITION BY `emp`.`department` ORDER BY `emp`.`salary` DESC)"
        @test isempty(params1)

        # RANK() OVER (ORDER BY salary DESC)
        wf2 = rank(over(order_by = [(col(:emp, :salary), true)]))
        params2 = Symbol[]
        sql2 = compile_expr(dialect, wf2, params2)
        @test sql2 == "RANK() OVER (ORDER BY `emp`.`salary` DESC)"

        # DENSE_RANK() OVER ()
        wf3 = dense_rank(over())
        params3 = Symbol[]
        sql3 = compile_expr(dialect, wf3, params3)
        @test sql3 == "DENSE_RANK() OVER ()"

        # NTILE(4) OVER (ORDER BY salary DESC)
        wf4 = ntile(4, over(order_by = [(col(:emp, :salary), true)]))
        params4 = Symbol[]
        sql4 = compile_expr(dialect, wf4, params4)
        @test sql4 == "NTILE(4) OVER (ORDER BY `emp`.`salary` DESC)"
    end

    @testset "Window Function SQL Compilation - Value Functions" begin
        dialect = SQLiteDialect()

        # LAG(price) OVER (ORDER BY date)
        wf1 = lag(col(:prices, :price),
                  over(order_by = [(col(:prices, :date), false)]))
        sql1 = compile_expr(dialect, wf1, Symbol[])
        @test sql1 == "LAG(`prices`.`price`, 1) OVER (ORDER BY `prices`.`date`)"

        # LAG(price, 3, 0) OVER (ORDER BY date)
        wf2 = lag(col(:prices, :price),
                  over(order_by = [(col(:prices, :date), false)]),
                  3, literal(0))
        sql2 = compile_expr(dialect, wf2, Symbol[])
        @test sql2 == "LAG(`prices`.`price`, 3, 0) OVER (ORDER BY `prices`.`date`)"

        # LEAD(price, 1) OVER (ORDER BY date)
        wf3 = lead(col(:prices, :price),
                   over(order_by = [(col(:prices, :date), false)]))
        sql3 = compile_expr(dialect, wf3, Symbol[])
        @test sql3 == "LEAD(`prices`.`price`, 1) OVER (ORDER BY `prices`.`date`)"

        # FIRST_VALUE(salary) OVER (PARTITION BY dept ORDER BY hire_date)
        wf4 = first_value(col(:emp, :salary),
                          over(partition_by = [col(:emp, :dept)],
                               order_by = [(col(:emp, :hire_date), false)]))
        sql4 = compile_expr(dialect, wf4, Symbol[])
        @test sql4 ==
              "FIRST_VALUE(`emp`.`salary`) OVER (PARTITION BY `emp`.`dept` ORDER BY `emp`.`hire_date`)"

        # NTH_VALUE(salary, 2) OVER (PARTITION BY dept ORDER BY salary DESC)
        wf5 = nth_value(col(:emp, :salary), 2,
                        over(partition_by = [col(:emp, :dept)],
                             order_by = [(col(:emp, :salary), true)]))
        sql5 = compile_expr(dialect, wf5, Symbol[])
        @test sql5 ==
              "NTH_VALUE(`emp`.`salary`, 2) OVER (PARTITION BY `emp`.`dept` ORDER BY `emp`.`salary` DESC)"
    end

    @testset "Window Function SQL Compilation - Aggregates with Frames" begin
        dialect = SQLiteDialect()

        # SUM(amount) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        wf1 = win_sum(col(:sales, :amount),
                      over(order_by = [(col(:sales, :date), false)],
                           frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)))
        sql1 = compile_expr(dialect, wf1, Symbol[])
        @test sql1 ==
              "SUM(`sales`.`amount`) OVER (ORDER BY `sales`.`date` ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)"

        # AVG(close) OVER (ORDER BY date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)
        wf2 = win_avg(col(:prices, :close),
                      over(order_by = [(col(:prices, :date), false)],
                           frame = window_frame(:ROWS, -29, :CURRENT_ROW)))
        sql2 = compile_expr(dialect, wf2, Symbol[])
        @test sql2 ==
              "AVG(`prices`.`close`) OVER (ORDER BY `prices`.`date` ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)"

        # MIN(value) OVER (PARTITION BY category ORDER BY date RANGE BETWEEN 5 PRECEDING AND 2 FOLLOWING)
        wf3 = win_min(col(:data, :value),
                      over(partition_by = [col(:data, :category)],
                           order_by = [(col(:data, :date), false)],
                           frame = window_frame(:RANGE, -5, 2)))
        sql3 = compile_expr(dialect, wf3, Symbol[])
        @test sql3 ==
              "MIN(`data`.`value`) OVER (PARTITION BY `data`.`category` ORDER BY `data`.`date` RANGE BETWEEN 5 PRECEDING AND 2 FOLLOWING)"

        # MAX(value) OVER (ORDER BY id ROWS UNBOUNDED PRECEDING)
        wf4 = win_max(col(:events, :value),
                      over(order_by = [(col(:events, :id), false)],
                           frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING)))
        sql4 = compile_expr(dialect, wf4, Symbol[])
        @test sql4 ==
              "MAX(`events`.`value`) OVER (ORDER BY `events`.`id` ROWS UNBOUNDED PRECEDING)"
    end

    @testset "Window Functions in SELECT" begin
        dialect = SQLiteDialect()

        # SELECT name, salary, ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rank
        # FROM employees
        q = from(:employees) |>
            select(NamedTuple,
                   col(:employees, :name),
                   col(:employees, :salary),
                   row_number(over(partition_by = [col(:employees, :dept)],
                                   order_by = [(col(:employees, :salary), true)])))

        sql, params = compile(dialect, q)
        @test occursin("ROW_NUMBER() OVER (PARTITION BY `employees`.`dept` ORDER BY `employees`.`salary` DESC)",
                       sql)
        @test occursin("SELECT", sql)
        @test occursin("FROM `employees`", sql)

        # Running total with window function
        q2 = from(:sales) |>
             select(NamedTuple,
                    col(:sales, :date),
                    col(:sales, :amount),
                    win_sum(col(:sales, :amount),
                            over(order_by = [(col(:sales, :date), false)],
                                 frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING,
                                                      :CURRENT_ROW))))

        sql2, params2 = compile(dialect, q2)
        @test occursin("SUM(`sales`.`amount`) OVER (ORDER BY `sales`.`date` ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
                       sql2)
    end

    @testset "Window Function Equality" begin
        # WindowFrame equality
        f1 = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)
        f2 = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW)
        f3 = window_frame(:RANGE, :UNBOUNDED_PRECEDING, :CURRENT_ROW)
        @test isequal(f1, f2)
        @test !isequal(f1, f3)

        # Over equality
        o1 = over(partition_by = [col(:t, :a)], order_by = [(col(:t, :b), true)])
        o2 = over(partition_by = [col(:t, :a)], order_by = [(col(:t, :b), true)])
        o3 = over(partition_by = [col(:t, :a)], order_by = [(col(:t, :b), false)])
        @test isequal(o1, o2)
        @test !isequal(o1, o3)

        # WindowFunc equality
        w1 = row_number(over(order_by = [(col(:t, :a), false)]))
        w2 = row_number(over(order_by = [(col(:t, :a), false)]))
        w3 = rank(over(order_by = [(col(:t, :a), false)]))
        @test isequal(w1, w2)
        @test !isequal(w1, w3)
    end

    @testset "Window Function Hashing" begin
        # Test that window functions can be used in Sets/Dicts
        w1 = row_number(over(order_by = [(col(:t, :a), false)]))
        w2 = row_number(over(order_by = [(col(:t, :a), false)]))
        w3 = rank(over(order_by = [(col(:t, :a), false)]))

        s = Set([w1, w2, w3])
        @test length(s) == 2  # w1 and w2 should be deduplicated
    end
end
