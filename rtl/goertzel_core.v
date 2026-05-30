`timescale 1ns / 1ps
/*
 * goertzel_core.v
 *
 * Fixed-point coherent-bin Goertzel DFT extractor.
 *
 * Purpose:
 *   Extract one complex DFT bin from a signed ADC stream with deterministic
 *   block latency. Intended for lock-in / pilot-tone phasor extraction.
 *
 * Algorithm:
 *   s[n] = x[n] + 2*cos(w)*s[n-1] - s[n-2]
 *   I    = s[N] - s[N-1]*cos(w)
 *   Q    = s[N-1]*sin(w)
 *
 * Coefficients:
 *   COEFF_2COS_Q17 = round(2*cos(w) * 2^17)
 *   COS_Q17        = round(cos(w)   * 2^17)
 *   SIN_Q17        = round(sin(w)   * 2^17)
 *
 * Safety policy:
 *   - All recurrence/feedforward intermediates are computed wide.
 *   - overflow_block pulses at block completion if any overflow occurred.
 *   - overflow_sticky stays high until clear_overflow is asserted.
 *   - dout_valid only asserts when the block completed without overflow.
 *   - block_done asserts for every completed block, including overflowed blocks.
 *
 * Scale:
 *   For a coherent cosine tone, amplitude ~= 2*sqrt(I^2+Q^2)/N_BLOCK.
 */
module goertzel_core #(
    parameter integer N_BLOCK              = 1000,
    parameter signed [17:0] COEFF_2COS_Q17 = 18'sd32855,
    parameter signed [17:0] COS_Q17        = 18'sd16428,
    parameter signed [17:0] SIN_Q17        = 18'sd130038
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire signed [15:0] din,
    input  wire               din_valid,
    input  wire               clear_overflow,

    output reg  signed [47:0] i_out,
    output reg  signed [47:0] q_out,
    output reg                dout_valid,
    output reg                block_done,
    output reg                overflow_block,
    output reg                overflow_sticky,
    output reg  [31:0]        block_counter
);

    localparam signed [47:0] S48_MAX = 48'sh7FFF_FFFF_FFFF;
    localparam signed [47:0] S48_MIN = 48'sh8000_0000_0000;

    reg signed [47:0] s_prev1; // s[n-1]
    reg signed [47:0] s_prev2; // s[n-2]
    reg [31:0] count;
    reg overflow_accum;

    wire signed [47:0] din_ext = {{32{din[15]}}, din};

    // Recurrence path, wide enough to detect before truncation.
    wire signed [65:0] mult_2cos_wide = s_prev1 * COEFF_2COS_Q17;
    wire signed [65:0] feedback_wide  = mult_2cos_wide >>> 17;

    wire signed [66:0] din_wide     = {{19{din_ext[47]}}, din_ext};
    wire signed [66:0] feedback_ext = {feedback_wide[65], feedback_wide};
    wire signed [66:0] prev2_wide   = {{19{s_prev2[47]}}, s_prev2};
    wire signed [66:0] s_curr_wide  = din_wide + feedback_ext - prev2_wide;

    wire signed [66:0] S48_MAX_EXT = {{19{S48_MAX[47]}}, S48_MAX};
    wire signed [66:0] S48_MIN_EXT = {{19{S48_MIN[47]}}, S48_MIN};

    wire s_curr_overflow = (s_curr_wide > S48_MAX_EXT) || (s_curr_wide < S48_MIN_EXT);
    wire signed [47:0] s_curr = s_curr_wide[47:0];

    // Feedforward path for final sample.
    wire signed [65:0] prev1_cos_wide  = s_prev1 * COS_Q17;
    wire signed [65:0] prev1_sin_wide  = s_prev1 * SIN_Q17;
    wire signed [65:0] prev1_cos_shift = prev1_cos_wide >>> 17;
    wire signed [65:0] prev1_sin_shift = prev1_sin_wide >>> 17;

    wire signed [66:0] curr_ext      = {{19{s_curr[47]}}, s_curr};
    wire signed [66:0] prev1_cos_ext = {prev1_cos_shift[65], prev1_cos_shift};
    wire signed [66:0] prev1_sin_ext = {prev1_sin_shift[65], prev1_sin_shift};

    wire signed [66:0] real_wide = curr_ext - prev1_cos_ext;
    wire signed [66:0] imag_wide = prev1_sin_ext;

    wire real_overflow = (real_wide > S48_MAX_EXT) || (real_wide < S48_MIN_EXT);
    wire imag_overflow = (imag_wide > S48_MAX_EXT) || (imag_wide < S48_MIN_EXT);

    wire final_sample = (count == (N_BLOCK - 1));
    wire overflow_any_next = overflow_accum | s_curr_overflow | (final_sample & (real_overflow | imag_overflow));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_prev1         <= 48'sd0;
            s_prev2         <= 48'sd0;
            count           <= 32'd0;
            i_out           <= 48'sd0;
            q_out           <= 48'sd0;
            dout_valid      <= 1'b0;
            block_done      <= 1'b0;
            overflow_block  <= 1'b0;
            overflow_sticky <= 1'b0;
            overflow_accum  <= 1'b0;
            block_counter   <= 32'd0;
        end else begin
            dout_valid     <= 1'b0;
            block_done     <= 1'b0;
            overflow_block <= 1'b0;

            if (clear_overflow) begin
                overflow_sticky <= 1'b0;
            end

            if (din_valid) begin
                if (final_sample) begin
                    block_done     <= 1'b1;
                    overflow_block <= overflow_any_next;
                    overflow_sticky <= overflow_sticky | overflow_any_next;
                    block_counter  <= block_counter + 32'd1;

                    if (!overflow_any_next) begin
                        i_out      <= real_wide[47:0];
                        q_out      <= imag_wide[47:0];
                        dout_valid <= 1'b1;
                    end

                    s_prev1        <= 48'sd0;
                    s_prev2        <= 48'sd0;
                    count          <= 32'd0;
                    overflow_accum <= 1'b0;
                end else begin
                    s_prev2        <= s_prev1;
                    s_prev1        <= s_curr;
                    count          <= count + 32'd1;
                    overflow_accum <= overflow_accum | s_curr_overflow;
                end
            end
        end
    end

endmodule
