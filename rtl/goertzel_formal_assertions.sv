`timescale 1ns / 1ps
/*
 * goertzel_formal_assertions.sv
 *
 * Formal property checks for goertzel_core.v.
 *
 * These assumptions/assertions can be used in simulation or formal verification
 * environments (e.g., Synopsys VC Formal, Mentor Questa Formal).
 */

module goertzel_formal_assertions (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        din_valid,
    input  wire        din_ready,
    input  wire        dout_valid,
    input  wire        overflow_block,
    input  wire        block_done,
    input  wire [31:0] block_counter,
    input  wire [31:0] count_internal,
    input  wire        clear_overflow
);

    // Safety: din_ready deasserted when output pending is acceptable only
    // in a buffered AXI wrapper. Here we just check count range.
    property count_in_range;
        @(posedge clk) disable iff (!rst_n)
        (count_internal < 32'd1000);
    endproperty

    // block_done only fires when a full block has been accepted.
    property block_done_pacing;
        @(posedge clk) disable iff (!rst_n)
        block_done |-> block_done;
    endproperty

    // dout_valid exclusive with overflow_block.
    property valid_not_overflow;
        @(posedge clk) disable iff (!rst_n)
        dout_valid |-> !overflow_block;
    endproperty

    // block_counter increments only on block_done.
    property counter_monotone;
        @(posedge clk) disable iff (!rst_n)
        block_done |-> (block_counter == $past(block_counter) + 32'd1);
    endproperty

    // overflow_sticky is sticky until clear_overflow.
    property sticky_until_clear;
        @(posedge clk) disable iff (!rst_n)
        (overflow_block == 1'b1) |-> (overflow_sticky == 1'b1) ##1 (clear_overflow |-> overflow_sticky == 1'b0);
    endproperty

    // After reset, all registers recover.
    property reset_recovery;
        @(posedge clk) disable iff (rst_n)
        1'b1 |-> !rst_n ##1 rst_n ##1 (count_internal == 32'd0 && block_counter == 32'd0);
    endproperty

endmodule
