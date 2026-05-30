`timescale 1ns / 1ps
/*
 * AXI-Stream wrapper for goertzel_core.
 *
 * Holds one output phasor until m_axis_tready. Input backpressure is asserted
 * while an output is pending to prevent block-boundary ambiguity.
 */
module goertzel_axis_core #(
    parameter integer N_BLOCK              = 1000,
    parameter signed [17:0] COEFF_2COS_Q17 = 18'sd32855,
    parameter signed [17:0] COS_Q17        = 18'sd16428,
    parameter signed [17:0] SIN_Q17        = 18'sd130038,
    parameter [31:0]        COEFF_ID       = 32'h0002_3000
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire signed [15:0] s_axis_tdata,
    input  wire               s_axis_tvalid,
    output wire               s_axis_tready,

    output reg                m_axis_tvalid,
    input  wire               m_axis_tready,
    output reg  signed [47:0] m_axis_i,
    output reg  signed [47:0] m_axis_q,
    output reg                m_axis_overflow,
    output reg  [31:0]        m_axis_block_index,
    output wire [31:0]        m_axis_coeff_id,

    input  wire               clear_overflow,
    output wire               overflow_sticky
);

    assign m_axis_coeff_id = COEFF_ID;
    assign s_axis_tready = !m_axis_tvalid;

    wire core_accept = s_axis_tvalid && s_axis_tready;

    wire signed [47:0] core_i;
    wire signed [47:0] core_q;
    wire core_dout_valid;
    wire core_block_done;
    wire core_overflow_block;
    wire [31:0] core_block_counter;

    goertzel_core #(
        .N_BLOCK(N_BLOCK),
        .COEFF_2COS_Q17(COEFF_2COS_Q17),
        .COS_Q17(COS_Q17),
        .SIN_Q17(SIN_Q17)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .din(s_axis_tdata),
        .din_valid(core_accept),
        .clear_overflow(clear_overflow),
        .i_out(core_i),
        .q_out(core_q),
        .dout_valid(core_dout_valid),
        .block_done(core_block_done),
        .overflow_block(core_overflow_block),
        .overflow_sticky(overflow_sticky),
        .block_counter(core_block_counter)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid      <= 1'b0;
            m_axis_i           <= 48'sd0;
            m_axis_q           <= 48'sd0;
            m_axis_overflow    <= 1'b0;
            m_axis_block_index <= 32'd0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (core_block_done) begin
                m_axis_i           <= core_i;
                m_axis_q           <= core_q;
                m_axis_overflow    <= core_overflow_block;
                m_axis_block_index <= core_block_counter;
                m_axis_tvalid      <= 1'b1;
            end
        end
    end

endmodule
