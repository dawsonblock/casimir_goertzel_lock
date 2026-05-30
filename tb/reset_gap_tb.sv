`timescale 1ns / 1ps
/*
 * reset_gap_tb.sv
 *
 * Stress-test scenarios for goertzel_core.v:
 *  - din_valid gating (sample gaps inside a block)
 *  - reset recovery during ongoing block
 *  - back-to-back blocks without idle cycles
 */
module reset_gap_tb;

    localparam integer N_BLOCK = 1000;

    logic                clk;
    logic                rst_n;
    logic signed [15:0]  din;
    logic                din_valid;
    logic                clear_overflow;

    logic signed [47:0]  i_out;
    logic signed [47:0]  q_out;
    logic                dout_valid;
    logic                block_done;
    logic                overflow_block;
    logic                overflow_sticky;
    logic [31:0]         block_counter;

    goertzel_core #(
        .N_BLOCK(N_BLOCK),
        .COEFF_2COS_Q17(18'sd32855),
        .COS_Q17(18'sd16428),
        .SIN_Q17(18'sd130038)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .din(din),
        .din_valid(din_valid),
        .clear_overflow(clear_overflow),
        .i_out(i_out),
        .q_out(q_out),
        .dout_valid(dout_valid),
        .block_done(block_done),
        .overflow_block(overflow_block),
        .overflow_sticky(overflow_sticky),
        .block_counter(block_counter)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic send_with_gap_at (
        input int gap_index,
        input int total_samples,
        input logic signed [15:0] sample_value
    );
        for (int i = 0; i < total_samples; i = i + 1) begin
            @(posedge clk);
            if (i == gap_index) begin
                din_valid <= 1'b0;
                din <= 16'sd0;
                @(posedge clk);
                din_valid <= 1'b0;
                din <= 16'sd0;
                @(posedge clk);
            end
            din <= sample_value;
            din_valid <= 1'b1;
        end
        din_valid <= 1'b0;
        din <= 16'sd0;
    endtask

    task automatic stream_n_samples (
        input int n_samples,
        input logic signed [15:0] sample_value
    );
        for (int i = 0; i < n_samples; i = i + 1) begin
            @(posedge clk);
            din <= sample_value;
            din_valid <= 1'b1;
        end
        din_valid <= 1'b0;
        din <= 16'sd0;
    endtask

    task automatic wait_for_block (
        inout int timeout_cycles,
        inout int failures
    );
        timeout_cycles = 0;
        while (!block_done && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!block_done) begin
            $display("FAIL: block_done never asserted.");
            failures = failures + 1;
        end
    endtask

    initial begin
        int timeout_cycles;
        int failures;
        int i;

        failures = 0;

        rst_n = 1'b0;
        din = 16'sd0;
        din_valid = 1'b0;
        clear_overflow = 1'b0;

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        $display("\n--- Test 1: din_valid gap at sample 100 ---");
        send_with_gap_at(100, N_BLOCK, 16'sd5120);
        wait_for_block(timeout_cycles, failures);
        if (!failures) $display("PASS: block completed despite gap.");

        if (!failures) begin
            if (dout_valid) begin
                $display("  dout_valid=%0d, block_counter=%0d", dout_valid, block_counter);
            end else begin
                $display("  dout_valid=%0d (overflow or invalid)", dout_valid);
            end
        end

        @(posedge clk);
        rst_n <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        $display("\n--- Test 2: reset mid-block at sample 400 ---");
        din <= 16'sd3200;
        din_valid <= 1'b1;
        for (i = 0; i < 400; i = i + 1) begin
            @(posedge clk);
        end
        rst_n <= 1'b0;
        din_valid <= 1'b0;
        din <= 16'sd0;
        @(posedge clk);
        rst_n <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
        stream_n_samples(N_BLOCK - 400 + 10, 16'sd6400);
        wait_for_block(timeout_cycles, failures);
        if (!failures) $display("PASS: block completed after reset recovery.");

        @(posedge clk);
        rst_n <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        $display("\n--- Test 3: back-to-back blocks, no idle cycles ---");
        din_valid <= 1'b1;
        din <= 16'sd2560;
        for (i = 0; i < N_BLOCK; i = i + 1) begin
            @(posedge clk);
        end
        din <= 16'sd2560;
        for (i = 0; i < N_BLOCK; i = i + 1) begin
            @(posedge clk);
        end
        din_valid <= 1'b0;
        din <= 16'sd0;

        timeout_cycles = 0;
        while (block_counter < 32'd3 && timeout_cycles < 3000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (block_counter == 32'd3) begin
            $display("PASS: block_counter reached %0d after back-to-back blocks.", block_counter);
        end else begin
            $display("FAIL: block_counter=%0d, expected 3 after back-to-back blocks.", block_counter);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("\nPASS: All reset/gap stress tests passed.");
        else
            $display("\nFAIL: %0d stress test(s) failed.", failures);

        $finish;
    end

endmodule
