`timescale 1ns / 1ps
/*
 * goertzel_axis_tb.sv
 *
 * Testbench for goertzel_axis_core.v (AXI-Stream wrapper).
 *
 * Exercises:
 *  1. Continuous stream with immediate transfer (no stall).
 *  2. Stall 100 cycles after block boundary, then repeat.
 *  3. Backpressure during reception.
 */
module goertzel_axis_tb;

    localparam integer N_BLOCK = 1000;

    logic                clk;
    logic                rst_n;
    logic signed [15:0]  s_axis_tdata;
    logic                s_axis_tvalid;
    logic                s_axis_tready;
    logic                m_axis_tready;
    logic                m_axis_tvalid;
    logic signed [47:0]  m_axis_i;
    logic signed [47:0]  m_axis_q;
    logic                m_axis_overflow;
    logic [31:0]         m_axis_block_index;
    logic [31:0]         m_axis_coeff_id;
    logic                clear_overflow;

    localparam NUM_BLOCKS = 2;

    // Stimulus memories.
    logic signed [15:0] adc_mem [0:N_BLOCK-1];

    goertzel_axis_core #(
        .N_BLOCK(N_BLOCK),
        .COEFF_2COS_Q17(18'sd32855),
        .COS_Q17(18'sd16428),
        .SIN_Q17(18'sd130038),
        .COEFF_ID(32'h2301_2300)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tready(m_axis_tready),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_i(m_axis_i),
        .m_axis_q(m_axis_q),
        .m_axis_overflow(m_axis_overflow),
        .m_axis_block_index(m_axis_block_index),
        .m_axis_coeff_id(m_axis_coeff_id),
        .clear_overflow(clear_overflow),
        .overflow_sticky()
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic stream_block (
        input stall_after_samples,
        input stall_cycles,
        input int vector_dir_number
    );
        int i;
        for (i = 0; i < N_BLOCK; i = i + 1) begin
            @(posedge clk);
            s_axis_tdata  <= 16'sd6400;
            s_axis_tvalid <= 1'b1;
            if (stall_after_samples > 0 && i == stall_after_samples - 1) begin
                @(posedge clk);
                s_axis_tvalid <= 1'b0;
                s_axis_tdata  <= 16'sd0;
                repeat (stall_cycles) @(posedge clk);
            end
        end
        s_axis_tvalid <= 1'b0;
        s_axis_tdata  <= 16'sd0;
        @(posedge clk);
    endtask

    initial begin
        int i;
        int timeout_cycles;
        int failures;
        int block_index_expected;

        failures = 0;

        rst_n = 1'b0;
        s_axis_tdata  = 16'sd0;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b0;
        clear_overflow = 1'b0;

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // Initialize ADC memory with partial cosine for coherent tone.
        for (i = 0; i < N_BLOCK; i = i + 1)
            adc_mem[i] = 16'sd6400;

        // Load ADC mem into stream.
        for (i = 0; i < N_BLOCK; i = i + 1)
            adc_mem[i] = 16'sd6400;

        // ---- Test 1: no stall ----
        $display("\n--- Test 1: no stall. stream and expect 1 block. ---");
        m_axis_tready = 1'b1;
        stream_block(0, 0, 1);

        timeout_cycles = 0;
        while (!m_axis_tvalid && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!m_axis_tvalid) begin
            $display("FAIL: m_axis_tvalid did not assert.");
            failures = failures + 1;
        end else begin
            $display("PASS: m_axis_tvalid asserted.");
            $display("  block_index=%0d", m_axis_block_index);
        end

        @(posedge clk);
        rst_n <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // ---- Test 2: stall 100 cycles after partial samples ----
        $display("\n--- Test 2: stall 100 cycles after 200 samples. ---");
        m_axis_tready = 1'b1;
        stream_block(200, 100, 2);

        // Consume first output.
        m_axis_tready = 1'b1;
        timeout_cycles = 0;
        while (!m_axis_tvalid && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!m_axis_tvalid) begin
            $display("FAIL: m_axis_tvalid did not assert after stall.");
            failures = failures + 1;
        end else begin
            $display("PASS: m_axis_tvalid after stall. block_index=%0d", m_axis_block_index);
        end

        @(posedge clk);
        rst_n <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        // ---- Test 3: backpressure during block reception ----
        $display("\n--- Test 3: backpressure during block reception. ---");
        m_axis_tready = 1'b0;
        stream_block(0, 0, 3);
        #20;
        m_axis_tready = 1'b1;
        #20;

        timeout_cycles = 0;
        while (!m_axis_tvalid && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!m_axis_tvalid) begin
            $display("FAIL: m_axis_tvalid did not assert after backpressure.");
            failures = failures + 1;
        end else begin
            $display("PASS: m_axis_tvalid after backpressure. block_index=%0d", m_axis_block_index);
        end

        if (failures == 0)
            $display("\nPASS: All AXI wrapper tests passed.");
        else
            $display("\nFAIL: %0d test(s) failed.", failures);

        $finish;
    end

endmodule
