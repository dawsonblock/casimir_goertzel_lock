`timescale 1ns / 1ps
/*
 * goertzel_regbank.v
 *
 * AXI-Lite-style register bank for goertzel_core control and status.
 *
 * Provides:
 *  - RW coefficient registers (coeff_2cos, coeff_cos, coeff_sin)
 *  - RO block_counter and overflow flags
 *  - Control register: clear_overflow
 *  - Coefficient ID / feature register (RO)
 *
 * Address map (word-addressed, 32-bit registers):
 *  0x00: coeff_2cos [31:0] (RW)
 *  0x04: coeff_cos  [31:0] (RW)
 *  0x08: coeff_sin  [31:0] (RW)
 *  0x0C: block_counter [31:0] (RO)
 *  0x10: status: {overflow_sticky, overflow_block, 30'b0} (RO)
 *  0x14: control: {31'b0, clear_overflow} (W1C / RW)
 *  0x18: coeff_id [31:0] (RO)
 */
module goertzel_regbank #(
    parameter COEFF_ID = 32'h0002_3000,
    parameter N_BLOCK_DEFAULT = 1000
)(
    input  wire               clk,
    input  wire               rst_n,

    // Wishbone-like interface (simplified for synthesis).
    input  wire        [3:0]  addr,
    input  wire               wr_en,
    input  wire               rd_en,
    input  wire        [31:0] wr_data,
    output reg         [31:0] rd_data,
    output reg                rd_ack,

    // Live clock enable for coefficient rewrites.
    output reg         [17:0] coeff_2cos,
    output reg         [17:0] coeff_cos,
    output reg         [17:0] coeff_sin,

    // Core status inputs.
    input  wire               block_done,
    input  wire               overflow_block,
    input  wire               overflow_sticky,
    input  wire        [31:0] block_counter,

    // Control outputs.
    output reg                clear_overflow
);

    localparam COEFF_2COS_DEFAULT = 18'sd32855;
    localparam COEFF_COS_DEFAULT  = 18'sd16428;
    localparam COEFF_SIN_DEFAULT  = 18'sd130038;

    // Register storage.
    reg signed [17:0]   reg_coeff_2cos;
    reg signed [17:0]   reg_coeff_cos;
    reg signed [17:0]   reg_coeff_sin;
    reg        [31:0]   reg_block_counter;
    reg                 reg_overflow_sticky;
    reg                 reg_overflow_block;

    wire addr_is_2cos  = (addr == 4'h0);
    wire addr_is_cos   = (addr == 4'h1);
    wire addr_is_sin   = (addr == 4'h2);
    wire addr_is_ctr   = (addr == 4'h3);
    wire addr_is_stat  = (addr == 4'h4);
    wire addr_is_ctrl  = (addr == 4'h5);
    wire addr_is_cid   = (addr == 4'h6);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_coeff_2cos      <= COEFF_2COS_DEFAULT;
            reg_coeff_cos       <= COEFF_COS_DEFAULT;
            reg_coeff_sin       <= COEFF_SIN_DEFAULT;
            reg_overflow_sticky <= 1'b0;
            reg_overflow_block  <= 1'b0;
            clear_overflow      <= 1'b0;
            rd_ack              <= 1'b0;
            rd_data             <= 32'd0;
        end else begin
            rd_ack <= 1'b0;
            clear_overflow <= 1'b0;

            if (wr_en) begin
                case (addr)
                    4'h0: reg_coeff_2cos <= wr_data[17:0];
                    4'h1: reg_coeff_cos  <= wr_data[17:0];
                    4'h2: reg_coeff_sin  <= wr_data[17:0];
                    4'h5: clear_overflow  <= wr_data[0];
                    default: ;
                endcase
            end

            if (block_done) begin
                reg_block_counter  <= block_counter;
                reg_overflow_block <= overflow_block;
                reg_overflow_sticky <= reg_overflow_sticky | overflow_block;
            end

            if (rd_en) begin
                rd_ack <= 1'b1;
                case (addr)
                    4'h0: rd_data <= {{14{reg_coeff_2cos[17]}}, reg_coeff_2cos};
                    4'h1: rd_data <= {{14{reg_coeff_cos[17]}},  reg_coeff_cos};
                    4'h2: rd_data <= {{14{reg_coeff_sin[17]}},  reg_coeff_sin};
                    4'h3: rd_data <= block_counter;
                    4'h4: rd_data <= {reg_overflow_sticky, reg_overflow_block, 30'd0};
                    4'h6: rd_data <= COEFF_ID;
                    default: rd_data <= 32'd0;
                endcase
            end
        end
    end

    // Latch outputs.
    always @(posedge clk) begin
        coeff_2cos <= reg_coeff_2cos;
        coeff_cos  <= reg_coeff_cos;
        coeff_sin  <= reg_coeff_sin;
    end

endmodule
