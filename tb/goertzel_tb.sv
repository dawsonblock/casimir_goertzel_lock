`timescale 1ns / 1ps

module goertzel_tb;

    localparam integer N_BLOCK = 1000;

    logic clk;
    logic rst_n;
    logic signed [15:0] din;
    logic din_valid;
    logic clear_overflow;

    logic signed [47:0] i_out;
    logic signed [47:0] q_out;
    logic dout_valid;
    logic block_done;
    logic overflow_block;
    logic overflow_sticky;
    logic [31:0] block_counter;

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

    logic [15:0] adc_mem [0:N_BLOCK-1];

    string vector_dir;
    string adc_path;
    string expected_path;

    integer fd_exp;
    integer scan_res;
    longint exp_i_out;
    longint exp_q_out;
    longint exp_s_n;
    longint exp_s_n_1;
    longint exp_max_abs;
    integer exp_overflow;

    logic signed [47:0] exp_i_48;
    logic signed [47:0] exp_q_48;

    integer i;
    integer timeout_cycles;

    initial begin
        $display("=================================================");
        $display("  GOERTZEL CORE SINGLE-VECTOR TESTBENCH");
        $display("=================================================");

        if (!$value$plusargs("VECTOR_DIR=%s", vector_dir)) begin
            vector_dir = "vectors/tone_phase_00";
        end

        adc_path = {vector_dir, "/adc.hex"};
        expected_path = {vector_dir, "/expected.txt"};

        $display("Vector dir: %s", vector_dir);
        $display("ADC path:   %s", adc_path);
        $display("EXP path:   %s", expected_path);

        fd_exp = $fopen(expected_path, "r");
        if (fd_exp == 0) begin
            $display("ERROR: Could not open expected file: %s", expected_path);
            $finish;
        end

        scan_res = $fscanf(fd_exp, "I_OUT_INTENDED: %d\n", exp_i_out);
        scan_res = $fscanf(fd_exp, "Q_OUT_INTENDED: %d\n", exp_q_out);
        scan_res = $fscanf(fd_exp, "S_N: %d\n", exp_s_n);
        scan_res = $fscanf(fd_exp, "S_N_MINUS_1: %d\n", exp_s_n_1);
        scan_res = $fscanf(fd_exp, "MAX_ABS_STATE: %d\n", exp_max_abs);
        scan_res = $fscanf(fd_exp, "OVERFLOW_EXPECTED: %d\n", exp_overflow);
        $fclose(fd_exp);

        exp_i_48 = exp_i_out[47:0];
        exp_q_48 = exp_q_out[47:0];

        $display("Expected I: %0d", exp_i_out);
        $display("Expected Q: %0d", exp_q_out);
        $display("Expected overflow: %0d", exp_overflow);

        $readmemh(adc_path, adc_mem);

        rst_n = 1'b0;
        din = 16'sd0;
        din_valid = 1'b0;
        clear_overflow = 1'b0;

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);

        for (i = 0; i < N_BLOCK; i = i + 1) begin
            @(posedge clk);
            din <= adc_mem[i];
            din_valid <= 1'b1;
        end

        @(posedge clk);
        din_valid <= 1'b0;
        din <= 16'sd0;

        timeout_cycles = 0;
        while (!block_done && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (!block_done) begin
            $display("ERROR: Simulation timed out waiting for block_done.");
            $finish;
        end

        // Give one cycle for any display from monitor.
        @(posedge clk);

        $display("ERROR: block_done observed but monitor did not finish. Check valid/overflow policy.");
        $finish;
    end

    always @(posedge clk) begin
        if (block_done) begin
            $display("-------------------------------------------------");
            $display("RTL block_done detected");
            $display("  dout_valid     = %0d", dout_valid);
            $display("  overflow_block = %0d", overflow_block);
            $display("  overflow_sticky= %0d", overflow_sticky);
            $display("  I_OUT          = %0d", i_out);
            $display("  Q_OUT          = %0d", q_out);
            $display("-------------------------------------------------");

            if (exp_overflow) begin
                if (overflow_block) begin
                    $display(">> VERDICT: PASS. Expected overflow was detected.");
                    $finish;
                end else begin
                    $display(">> VERDICT: FAIL. Expected overflow was not detected.");
                    $finish;
                end
            end

            if (!dout_valid) begin
                $display(">> VERDICT: FAIL. dout_valid did not assert for non-overflow vector.");
                $finish;
            end

            if (i_out === exp_i_48 && q_out === exp_q_48 && overflow_block === 1'b0) begin
                $display(">> VERDICT: PASS. RTL exactly matches Python Golden Model.");
            end else begin
                $display(">> VERDICT: FAIL.");
                if (i_out !== exp_i_48) begin
                    $display("   I mismatch. Expected %0d, got %0d", exp_i_48, i_out);
                end
                if (q_out !== exp_q_48) begin
                    $display("   Q mismatch. Expected %0d, got %0d", exp_q_48, q_out);
                end
                if (overflow_block !== 1'b0) begin
                    $display("   Unexpected overflow_block.");
                end
            end

            $display("=================================================");
            $finish;
        end
    end

endmodule
