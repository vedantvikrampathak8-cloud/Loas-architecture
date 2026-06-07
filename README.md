# LoAS Dual-Sparse SNN Accelerator — RTL Implementation

SystemVerilog implementation of the LoAS accelerator architecture. Processes sparse input spike trains against sparse weight bitmasks using an inner-join with pseudo-accumulation and correction.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| T | 4 | Timesteps per inference pass |
| N_TPPE | 16 | Output neurons computed in parallel |
| BM_WIDTH | 128 | Input neuron count (bitmask width) |
| W_WIDTH | 8 | Weight bit width |
| ACC_WIDTH | 32 | Accumulator bit width |
| OFF_W | 7 | ceil(log2(BM_WIDTH)) — prefix sum offset width |
| N_ADDERS | 8 | Laggy prefix adder lanes (latency = BM_WIDTH/N_ADDERS) |
| FIFO_DEPTH | 128 | Match FIFO depth, must be >= BM_WIDTH |
| THRESHOLD | 1 | LIF firing threshold |

## Files

| File | Description |
|------|-------------|
| `fast_prefix_sum.sv` | Combinational Kogge-Stone prefix tree over bm_b |
| `laggy_prefix_sum.sv` | Sequential adder-chain prefix over bm_a, 16-cycle latency |
| `fifo.sv` | Parametric sync FIFO with fall-through read |
| `inner_join_unit.sv` | AND + prefix sums + FIFOs + pseudo/correction accumulators |
| `p_lif.sv` | Spatially unrolled LIF, T comparators in parallel |
| `tppe.sv` | Wraps inner_join_unit + p_lif for one output neuron |
| `top_loas.sv` | 16x TPPE array with bm_b broadcast |
| `tb_top_loas.sv` | Directed testbench, 4 test cases |

## Test Cases

| Test | Input | Expected Output |
|------|-------|-----------------|
| T1 | bm_a = bm_b = all-ones, spikes = 1111, weight = 1 | spike = 1111 (membrane = 128) |
| T2 | bm_a = bm_b = all-ones, spikes = 0000, weight = 1 | spike = 0000 (correction zeroes result) |
| T3 | bm_a and bm_b disjoint (AND = 0) | spike = 0000 (no matches) |
| T4 | 8 matches, spike pattern = 1010, weight = 4 | spike = 1010 (membrane[t1,t3] = 32, [t0,t2] = 0) |

## Simulation — Vivado (Tcl console)

Add all source files to the project first, then run all four tests from the Tcl console:

```tcl
add_files -scan_for_includes {
    fast_prefix_sum.sv
    laggy_prefix_sum.sv
    fifo.sv
    inner_join_unit.sv
    p_lif.sv
    tppe.sv
    top_loas.sv
}
add_files -scan_for_includes -fileset sim_1 tb_top_loas.sv
set_property top tb_top_loas [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
launch_simulation
run all
```

Expected output for all four tests passing:

```
T1: dense fire — all bits set, all spikes 1111
T1 TPPE[0] spike=1111 (expect 1111)
...
T2: dense no-fire — all bits set, all spikes 0000
T2 TPPE[0] spike=0000 (expect 0000)
...
T3: disjoint bitmasks — AND=0, no matches, result=0
T3 TPPE[0] spike=0000 (expect 0000)
...
T4: spike pattern 1010 on 8 matches — correction path
T4 TPPE[0] spike=1010 (expect 1010)
...
Done.
```
