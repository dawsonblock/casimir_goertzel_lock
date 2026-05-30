`timescale 1ns / 1ps
/*
 * goertzel_top.v
 *
 * Top-level integration module connecting science and pilot Goertzel channels
 * with a correction matrix for phase-rotation calibration.
 *
 * Architecture:
 *   ADC -> science Goertzel -> I/Q science -> correction matrix -> DMA/statistics
 *     \-> pilot Goertzel  -> I/Q pilot  -> phase drift estimator output
 *
 * Uses AXI-Stream wrappers with packed tdata for downstream connectivity.
 */

module goertzel_top #(
    parameter N_BLOCK = 1000,
    parameter COEFF_ID_SCIENCE = 32'h2301_2300,
    parameter COEFF_ID_PILOT   = 32'h2401_2400
)(
    input  wire               clk,
    input  wire               rst_n,

    // Common ADC input (shared sample clock).
    input  wire signed [15:0]  adc_data,
    input  wire                adc_valid,
    output wire                adc_ready,

    // Raw I/Q outputs from Goertzel cores.
    output wire signed [47:0]  science_i,
    output wire signed [47:0]  science_q,
    output wire                science_valid,
    output wire                science_overflow,

    output wire signed [47:0]  pilot_i,
    output wire signed [47:0]  pilot_q,
    output wire                pilot_valid,
    output wire                pilot_overflow,

    // Corrected science output (after rotation matrix).
    output wire signed [47:0]  science_i_corr,
    output wire signed [47:0]  science_q_corr,
    output wire                science_corr_valid,
    output wire                science_corr_overflow,

    // Correction matrix coefficients (Q30).
    input  wire signed [31:0]  m11_q30,
    input  wire signed [31:0]  m12_q30,
    input  wire signed [31:0]  m21_q30,
    input  wire signed [31:0]  m22_q30,

    // Control.
    input  wire                clear_overflow
);

    // Pack ADC into AXI-Stream style with tready demux.
    wire science_accept;
    wire pilot_accept;
    wire adc_ready_s;
    wire adc_ready_p;

    // Time-division-multiplex ADC based on per-core backpressure.
    // For simplicity, science has priority on the shared bus.
    // A production design would include a round-robin or arbiter.
    reg use_science;

    always @(*) begin
        if (science_accept) begin
            use_science = 1'b1;
        end else if (pilot_accept) begin
            use_science = 1'b0;
        end else begin
            use_science = 1'b1;
        end
    end

    wire sci_axis_tvalid = adc_valid && use_science;
    wire pilot_axis_tvalid = adc_valid && !use_science;

    assign adc_ready = science_accept || pilot_accept;

    // ---- Science channel ----
    goertzel_axis_core #(
        .N_BLOCK(N_BLOCK),
        .COEFF_2COS_Q17(18'sd32855),
        .COS_Q17(18'sd16428),
        .SIN_Q17(18'sd130038),
        .COEFF_ID(COEFF_ID_SCIENCE)
    ) u_science (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(adc_data),
        .s_axis_tvalid(sci_axis_tvalid),
        .s_axis_tready(science_accept),
        .m_axis_tvalid(science_valid),
        .m_axis_tready(1'b1),
        .m_axis_i(science_i),
        .m_axis_q(science_q),
        .m_axis_overflow(science_overflow),
        .m_axis_block_index(),
        .m_axis_coeff_id(),
        .clear_overflow(clear_overflow),
        .overflow_sticky()
    );

    // ---- Pilot channel ----
    goertzel_axis_core #(
        .N_BLOCK(N_BLOCK),
        .COEFF_2COS_Q17(18'sd16460),
        .COS_Q17(18'sd8230),
        .SIN_Q17(18'sd130813),
        .COEFF_ID(COEFF_ID_PILOT)
    ) u_pilot (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(adc_data),
        .s_axis_tvalid(pilot_axis_tvalid),
        .s_axis_tready(pilot_accept),
        .m_axis_tvalid(pilot_valid),
        .m_axis_tready(1'b1),
        .m_axis_i(pilot_i),
        .m_axis_q(pilot_q),
        .m_axis_overflow(pilot_overflow),
        .m_axis_block_index(),
        .m_axis_coeff_id(),
        .clear_overflow(clear_overflow),
        .overflow_sticky()
    );

    // ---- Correction matrix ----
    correction_matrix_q30 u_corr (
        .clk(clk),
        .rst_n(rst_n),
        .data_valid_in(science_valid),
        .i_raw(science_i),
        .q_raw(science_q),
        .m11_q30(m11_q30),
        .m12_q30(m12_q30),
        .m21_q30(m21_q30),
        .m22_q30(m22_q30),
        .data_valid_out(science_corr_valid),
        .i_corr(science_i_corr),
        .q_corr(science_q_corr),
        .overflow_flag(science_corr_overflow)
    );

endmodule
