/*!
 * <b>Module:</b> mclt16x16
 * @file mclt16x16.v
 * @date 2017-12-07  
 * @author eyesis
 *     
 * @brief Direct MCLT of 16x16 tile with subpixel window shift
 *
 * @copyright Copyright (c) 2017 <set up in Preferences-Verilog/VHDL Editor-Templates> .
 *
 * <b>License </b>
 *
 * mclt16x16.v is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * mclt16x16.v is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/> .
 *
 * Additional permission under GNU GPL version 3 section 7:
 * If you modify this Program, or any covered work, by linking or combining it
 * with independent modules provided by the FPGA vendor only (this permission
 * does not extend to any 3-rd party modules, "soft cores" or macros) under
 * different license terms solely for the purpose of generating binary "bitstream"
 * files and/or simulating the code, the copyright holders of this Program give
 * you the right to distribute the covered work without those independent modules
 * as long as the source code for them is available from the FPGA vendor free of
 * charge, and there is no dependence on any encrypted modules for simulating of
 * the combined code. This permission applies to you if the distributed code
 * contains all the components and scripts required to completely simulate it
 * with at least one of the Free Software programs.
 */
`timescale 1ns/1ps

module  mclt16x16#(
    parameter SHIFT_WIDTH =   8,    // bits in shift (1 bit - integer, 7 bits - fractional
    parameter COORD_WIDTH =  10,    // bits in full coordinate 10 for 18K RAM
    parameter PIXEL_WIDTH =  16,    // input pixel width (unsigned) 
    parameter WND_WIDTH =    18,    // input pixel width (unsigned) 
    parameter OUT_WIDTH =    24,    // bits in dtt output
    parameter DTT_IN_WIDTH = 24,    // bits in DTT input
    parameter TRANSPOSE_WIDTH = 24, // width of the transpose memory (intermediate results)    
    parameter OUT_RSHIFT =    2,    // overall right shift of the result from input, aligned by MSB (>=3 will never cause saturation)
    parameter OUT_RSHIFT2 =   0     // overall right shift for the second (vertical) pass
    
)(
    input                             clk,          //!< system clock, posedge
    input                             rst,           //!< sync reset
    input                             start,        //!< start convertion of the next 256 samples
    input           [SHIFT_WIDTH-1:0] x_shft,       //!< tile pixel X fractional shift (valid @ start) 
    input           [SHIFT_WIDTH-1:0] y_shft,       //!< tile pixel Y fractional shift (valid @ start)
    input                       [3:0] bayer,        // bayer mask (0 bits - skip pixel, valid @ start)
    output                      [7:0] mpixel_a,     //!< pixel address {y,x} of the input tile
    input           [PIXEL_WIDTH-1:0] mpixel_d,     //!< pixel data, latency = 2 from pixel address
    output                            pre2_rdy,     //!< after next cycle may be start of the next block          
    output                            pre_last_in,  //!< may increment page
    output                            pre_first_out,//!< next will output first of DCT/DCT coefficients          
    output                            pre_last_out, //!< next will be last output of DST/DST coefficients
    output                      [7:0] out_addr,     //!< address to save coefficients, 2 MSBs - mode (CC,SC,CS,SS), others - down first         
    output                            dv,           //!< output data valid
    output signed [OUT_WIDTH - 1 : 0] dout          //!<frequency domain data output            
);

    reg [SHIFT_WIDTH-1:0] x_shft_r;
    reg [SHIFT_WIDTH-1:0] y_shft_r;
    reg [SHIFT_WIDTH-1:0] x_shft_r2;
    reg [SHIFT_WIDTH-1:0] y_shft_r2;
    reg             [3:0] bayer_r;
    reg             [3:0] bayer_d; // same latency as mpix_a_w
    reg             [7:0] in_cntr; // input counter
    reg            [16:0] in_busy;
    wire           [17:0] fold_rom_out;
    wire           [ 7:0] mpix_a_w =   fold_rom_out[ 7:0];
    wire           [ 3:0] mpix_sgn_w = fold_rom_out[11:8];
    wire           [ 3:0] bayer_1hot = { mpix_a_w[4] &  mpix_a_w[0],  
                                         mpix_a_w[4] & ~mpix_a_w[0],
                                        ~mpix_a_w[4] &  mpix_a_w[0],
                                        ~mpix_a_w[4] & ~mpix_a_w[0]};
    wire                  mpix_use = |(bayer_d & bayer_1hot); //not disabled by bayer, valid with mpix_a_w
    wire                  mpix_use_d; // delayed
    reg                   mpix_use_r; // delayed
    wire           [ 3:0] mpix_sgn_d;
    reg            [ 3:0] mpix_sgn_r;
    wire  [WND_WIDTH-1:0] window_w;
    reg   [WND_WIDTH-1:0] window_r;
    reg [PIXEL_WIDTH-1:0] mpixel_d_r; // registered pixel data (to be absorbed by MPY)
    
    reg [PIXEL_WIDTH + WND_WIDTH - 1:0] pix_wnd_r; 
    reg   [DTT_IN_WIDTH-1:0] pix_wnd_r2; // pixels (positive) multiplied by window(positive), two MSBs == 2'b0 to prevent overflow
//    parameter DTT_IN_WIDTH = 24 
//    wire  [DTT_IN_WIDTH-3:0] pix_wnd = pix_wnd_r[PIXEL_WIDTH + WND_WIDTH - 1 -: DTT_IN_WIDTH-2];
    reg  [DTT_IN_WIDTH-1:0] data_cc_r;   
    reg  [DTT_IN_WIDTH-1:0] data_sc_r;   
    reg  [DTT_IN_WIDTH-1:0] data_cs_r;   
    reg  [DTT_IN_WIDTH-1:0] data_ss_r;
    // delay data to appear at different time slots from data_cc_r
    wire [DTT_IN_WIDTH-1:0] data_sc_w0; // delayed by 1 cycle   
    wire [DTT_IN_WIDTH-1:0] data_cs_w1; // delayed by 2 cycles   
    wire [DTT_IN_WIDTH-1:0] data_ss_w2; // delayed by 3 cycles
    reg  [DTT_IN_WIDTH-1:0] data_dtt_in; // multiplexed DTT input data
    
    reg               [1:0] mode_mux;   
    reg               [7:0] dtt_in_cntr; //
    reg                     dtt_in_page;
    wire              [8:0] dtt_in_wa = {dtt_in_page, dtt_in_cntr[1:0], dtt_in_cntr[7:2]};  
    wire                    dtt_we = in_busy[16];
    
    wire                     var_first_d; // adding subtracting first variant of 4 folds    
    reg                      var_first_r; // adding subtracting first variant of 4 folds
    wire                     var_last;    // next cycle the   data_xx_r will have data  (in_busy[14], ...)
    
// reading/converting DTT
    wire                    start_dtt = dtt_in_cntr == 196; // fune tune? ~= 3/4 of 256 
    reg               [7:0] dtt_r_cntr; //
    reg                     dtt_r_page;
    reg                     dtt_r_re;
    reg                     dtt_r_regen;
    reg                     dtt_start;
    wire              [1:0] dtt_mode = {dtt_r_cntr[7], dtt_r_cntr[6]}; // TODO: or reverse? 
    wire              [8:0] dtt_r_ra = {dtt_r_page,dtt_r_cntr};
    wire             [35:0] dtt_r_data_w; // high bits are not used 
    wire [DTT_IN_WIDTH-1:0] dtt_r_data = dtt_r_data_w[DTT_IN_WIDTH-1:0]; 
    
    always @ (posedge clk) begin
        if (start) begin
            x_shft_r <= x_shft;
            y_shft_r <= y_shft;
            bayer_r <= bayer;
        end
        if (in_busy[2]) begin      // same latency as mpix_a_w
            x_shft_r2 <= x_shft_r;
            y_shft_r2 <= y_shft_r;
        end
        
        if (in_busy[2]) bayer_d <= bayer_r; 
        
        if      (rst)      in_busy <= 0;
        else if (start)    in_busy <= 1;
        else               in_busy <= {in_busy[15:0], in_busy[0] & ~(&in_cntr)};
        
        if      (start)      in_cntr <= 0;
        else if (in_busy[0]) in_cntr[7:0] <= in_cntr[7:0] + 1;
        
        if (in_busy[8]) begin
            mpixel_d_r <= mpixel_d;
            window_r <=   window_w;
        end
        
        if (in_busy[9])  pix_wnd_r <= mpixel_d_r * window_r;
        
        if (in_busy[10]) pix_wnd_r2 <= {2'b00,pix_wnd_r[PIXEL_WIDTH + WND_WIDTH - 1 -: DTT_IN_WIDTH - 2]};
        if (in_busy[10]) begin
            mpix_use_r  <= mpix_use_d;
            var_first_r <= var_first_d;
            mpix_sgn_r <=  mpix_sgn_d; 
        end
        
        
        if (in_busy[11]) begin
            data_cc_r <= (var_first_r ? {DTT_IN_WIDTH{1'b0}} : data_cc_r) + mpix_use_r ? (mpix_sgn_r[0]?(-pix_wnd_r2):pix_wnd_r2): {DTT_IN_WIDTH{1'b0}} ;
            data_sc_r <= (var_first_r ? {DTT_IN_WIDTH{1'b0}} : data_sc_r) + mpix_use_r ? (mpix_sgn_r[1]?(-pix_wnd_r2):pix_wnd_r2): {DTT_IN_WIDTH{1'b0}} ;
            data_cs_r <= (var_first_r ? {DTT_IN_WIDTH{1'b0}} : data_cs_r) + mpix_use_r ? (mpix_sgn_r[2]?(-pix_wnd_r2):pix_wnd_r2): {DTT_IN_WIDTH{1'b0}} ;
            data_ss_r <= (var_first_r ? {DTT_IN_WIDTH{1'b0}} : data_ss_r) + mpix_use_r ? (mpix_sgn_r[3]?(-pix_wnd_r2):pix_wnd_r2): {DTT_IN_WIDTH{1'b0}} ;
        end
        
        if      (var_last)    mode_mux <= 0;
        else if (in_busy[15]) mode_mux <= mode_mux + 1;
        
        if (in_busy[15]) case (mode_mux)
            2'b00: data_dtt_in <= data_cc_r;
            2'b01: data_dtt_in <= data_sc_w0;
            2'b10: data_dtt_in <= data_cs_w1;
            2'b11: data_dtt_in <= data_ss_w2;
        endcase

        if (!in_busy[16]) dtt_in_cntr <= 0; 
        else              dtt_in_cntr <= dtt_in_cntr + 1;
        
        if (rst)               dtt_in_page <= 0;
        else if (&dtt_in_cntr) dtt_in_page <= dtt_in_page + 1;
        
        // reading memory and running DTT
        
        if (start_dtt)        dtt_r_page <=dtt_in_page;
        
        if (rst)              dtt_r_re <= 1'b0;
        else if (start_dtt)   dtt_r_re <= 1'b1;
        else if (&dtt_r_cntr) dtt_r_re <= 1'b0;
        dtt_r_regen <= dtt_r_re;
        
        if (!dtt_r_re) dtt_r_cntr <= 0;
        else           dtt_r_cntr <= dtt_r_cntr + 1;
        
        dtt_start <= dtt_r_cntr[5:0] == 0;
        
     
        
    end

/*
Calculate ROM for MCLT fold indices:
A0..A1 - variant, folding to the same 8x8 sample
A2..A4 - sample column in folded 8x8 tile
A5..A7 - sample row in folded 8x8 tile
D0..D4 - pixel column in 16x16 tile
D5..D7 - pixel row in 16x16 tile
D8 -  negate for mode 0 (CC)
D9 -  negate for mode 1 (SC)
D10 - negate for mode 2 (CS)      
D11 - negate for mode 3 (SS)

*/

// May serve 2 mclt16x16 channels when using 2 ports
     ram18tp_var_w_var_r #(
        .REGISTERS_A(1),
        .REGISTERS_B(1),
        .LOG2WIDTH_A(4),
        .LOG2WIDTH_B(4)
`ifdef PRELOAD_BRAMS
    `include "mclt_fold_rom.vh"
`endif
    ) i_mclt_fold_rom (
    
        .clk_a     (clk),       // input
        .addr_a    ({2'b0,in_cntr[1:0],in_cntr[7:2]}),    // input[9:0] 
        .en_a      (in_busy[1]),   // input
        .regen_a   (in_busy[2]),   // input
        .we_a      (1'b0),         // input
        .data_out_a(fold_rom_out), // output[17:0] 
        .data_in_a (18'b0),        // input[17:0]
        // port B may be used for other mclt16x16 
        .clk_b     (1'b0),         // input
        .addr_b    (10'b0),        // input[9:0] 
        .en_b      (1'b0),         // input
        .regen_b   (1'b0),         // input
        .we_b      (1'b0),         // input
        .data_out_b(),             // output[17:0] 
        .data_in_b (18'b0)         // input[17:0] 
    );

// Latency = 5
    mclt_wnd_mul #(
        .SHIFT_WIDTH (SHIFT_WIDTH),
        .COORD_WIDTH (COORD_WIDTH),
        .OUT_WIDTH   (WND_WIDTH)
    ) mclt_wnd_i (
        .clk       (clk), // input
        .en        (in_busy[3]), // input
        .x_in      (mpix_a_w[3:0]), // input[3:0] 
        .y_in      (mpix_a_w[7:4]), // input[3:0] 
        .x_shft    (x_shft_r2),     // input[7:0] 
        .y_shft    (y_shft_r2),     // input[7:0] 
        .wnd_out   (window_w) // output[17:0] valid with in_busy[8]
    );

// Matching window latency with pixel data latency
    dly_var #(
        .WIDTH(8),
        .DLY_WIDTH(4)
    ) dly_pixel_data_i (
        .clk  (clk),      // input
        .rst  (rst),      // input
        .dly  (4'h2),     // input[3:0] Delay for external memory latency = 2, reduce for higher 
        .din  (mpix_a_w), // input[0:0] 
        .dout (mpixel_a)  // output[0:0] 
    );

    dly_var #(
        .WIDTH(1),
        .DLY_WIDTH(4)
    ) dly_var_first_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h8),          // input[3:0] 
        .din  (in_busy[0] && (in_cntr[1:0] == 0)),  // input[0:0] 
        .dout (var_first_d)    // output[0:0] 
    );

    dly_var #(
        .WIDTH(1),
        .DLY_WIDTH(4)
    ) dly_mpix_use_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h6),          // input[3:0] 
        .din  (mpix_use),      // input[0:0] 
        .dout (mpix_use_d)     // output[0:0] 
    );

    dly_var #(
        .WIDTH(4),
        .DLY_WIDTH(4)
    ) dly_mpix_sgn_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h6),          // input[3:0] 
        .din  (mpix_sgn_w),    // input[0:0] 
        .dout (mpix_sgn_d)     // output[0:0] 
    );

    dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_data_sc_w0_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h0),          // input[3:0] 
        .din  (data_sc_r),      // input[0:0] 
        .dout (data_sc_w0)     // output[0:0] 
    );

    dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_data_cs_w1_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (data_cs_r),      // input[0:0] 
        .dout (data_cs_w1)     // output[0:0] 
    );

    dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_data_ss_w2_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h2),          // input[3:0] 
        .din  (data_ss_r),      // input[0:0] 
        .dout (data_ss_w2)     // output[0:0] 
    );

    dly_var #(
        .WIDTH(1),
        .DLY_WIDTH(4)
    ) dly_var_last_i (
        .clk  (clk),           // input
        .rst  (rst),           // input
        .dly  (4'h2),          // input[3:0] 
        .din  (var_first_r & in_busy[11]),      // input[0:0] 
        .dout (var_last)     // output[0:0] 
    );

    ram18p_var_w_var_r #(
        .REGISTERS(1),
        .LOG2WIDTH_WR(5),
        .LOG2WIDTH_RD(5)
    ) ram18p_var_w_var_r_dtt_in_i (
        .rclk     (clk),          // input
        .raddr    (dtt_r_ra),     // input[8:0] 
        .ren      (dtt_r_re),     // input
        .regen    (dtt_r_regen),  // input
        .data_out (dtt_r_data_w), // output[35:0] 
        .wclk     (clk),          // input
        .waddr    (dtt_in_wa),    // input[8:0] 
        .we       (dtt_we),       // input
        .web      (4'hf),         // input[3:0] 
        .data_in  ({{(36-DTT_IN_WIDTH){1'b0}}, data_dtt_in}) // input[35:0] 
    );


    dtt_iv_8x8 #(
        .INPUT_WIDTH     (DTT_IN_WIDTH),
        .OUT_WIDTH       (OUT_WIDTH),
        .OUT_RSHIFT1     (OUT_RSHIFT),
        .OUT_RSHIFT2     (OUT_RSHIFT2),
        .TRANSPOSE_WIDTH (TRANSPOSE_WIDTH),
        .DSP_B_WIDTH     (18),
        .DSP_A_WIDTH     (25),
        .DSP_P_WIDTH     (48)
    ) dtt_iv_8x8_i (
        .clk            (clk),              // input
        .rst            (rst),              // input
        .start          (dtt_start),  // input
        .mode           (dtt_mode),          // input[1:0] 
        .xin            (dtt_r_data),          // input[24:0] signed 
        .pre_last_in    (),   // output reg 
        .pre_first_out  (pre_first_out_2d), // output
        .dv             (dv),               // output
        .d_out          (dout),             // output[24:0] signed
        .mode_out       (mode_out),         // output[1:0] reg 
        .pre_busy       (pre_busy_2d)       // output reg 
    );





endmodule
