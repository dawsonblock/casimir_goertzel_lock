`timescale 1ns / 1ps
/*
 * 2x2 fixed-point correction matrix for phasor rotation / calibration.
 * Coefficients are signed Q30: 1.0 = 2^30.
 *
 * [I_corr]   [m11 m12] [I_raw]
 * [Q_corr] = [m21 m22] [Q_raw]
 */
module correction_matrix_q30 (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               data_valid_in,
    input  wire signed [47:0] i_raw,
    input  wire signed [47:0] q_raw,

    input  wire signed [31:0] m11_q30,
    input  wire signed [31:0] m12_q30,
    input  wire signed [31:0] m21_q30,
    input  wire signed [31:0] m22_q30,

    output reg                data_valid_out,
    output reg  signed [47:0] i_corr,
    output reg  signed [47:0] q_corr,
    output reg                overflow_flag
);

    localparam signed [79:0] S48_MAX_EXT = 80'sd140737488355327;
    localparam signed [79:0] S48_MIN_EXT = -80'sd140737488355328;

    wire signed [79:0] p11 = i_raw * m11_q30;
    wire signed [79:0] p12 = q_raw * m12_q30;
    wire signed [79:0] p21 = i_raw * m21_q30;
    wire signed [79:0] p22 = q_raw * m22_q30;

    wire signed [79:0] i_wide = (p11 + p12) >>> 30;
    wire signed [79:0] q_wide = (p21 + p22) >>> 30;

    wire i_overflow = (i_wide > S48_MAX_EXT) || (i_wide < S48_MIN_EXT);
    wire q_overflow = (q_wide > S48_MAX_EXT) || (q_wide < S48_MIN_EXT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_valid_out <= 1'b0;
            i_corr <= 48'sd0;
            q_corr <= 48'sd0;
            overflow_flag <= 1'b0;
        end else begin
            data_valid_out <= 1'b0;
            if (data_valid_in) begin
                if (i_overflow || q_overflow) begin
                    overflow_flag <= 1'b1;
                    data_valid_out <= 1'b0;
                end else begin
                    i_corr <= i_wide[47:0];
                    q_corr <= q_wide[47:0];
                    data_valid_out <= 1'b1;
                end
            end
        end
    end

endmodule
