/*!
 * <b>Module:</b>mclt_test_01
 * @file mclt_test_01.tf
 * @date 2016-12-02  
 * @author  Andrey Filippov
 *     
 * @brief testing MCLT 16x16 -> 4*8*8 transform
 * Uses 2 DSP blocks 
 *
 * @copyright Copyright (c) 2016 Elphel, Inc.
 *
 * <b>License:</b>
 *
 *mclt_test_01.tf is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 *  mclt_test_01.tf is distributed in the hope that it will be useful,
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
`include "system_defines.vh"
//  `define INSTANTIATE_DSP48E1
//  `define PRELOAD_BRAMS
//  `define ROUND 
module  mclt_test_06 ();
`ifdef IVERILOG              
    `ifdef NON_VDT_ENVIROMENT
        parameter fstname="mclt_test_06.fst";
    `else
        `include "IVERILOG_INCLUDE.v"
    `endif // NON_VDT_ENVIROMENT
`else // IVERILOG
    `ifdef CVC
        `ifdef NON_VDT_ENVIROMENT
            parameter fstname = "x393.fst";
        `else // NON_VDT_ENVIROMENT
            `include "IVERILOG_INCLUDE.v"
        `endif // NON_VDT_ENVIROMENT
    `else
        parameter fstname = "mclt_test_06.fst";
    `endif // CVC
`endif // IVERILOG
    
    parameter CLK_PERIOD =      10; // ns
//    parameter WIDTH =           25; //4; // input data width
    parameter SHIFT_WIDTH =      7; // bits in shift (7 bits - fractional)
    parameter COORD_WIDTH =     10; // bits in full coordinate 10 for 18K RAM
    parameter PIXEL_WIDTH =     16; // input pixel width (unsigned) 
    parameter WND_WIDTH =       18; // input pixel width (unsigned) 
    parameter OUT_WIDTH =       25; // bits in dtt output
    parameter DTT_IN_WIDTH =    25; // bits in DTT input
    parameter TRANSPOSE_WIDTH = 25; // width of the transpose memory (intermediate results)    
    parameter OUT_RSHIFT1 =      2; // overall right shift of the result from input, aligned by MSB (>=3 will never cause saturation)
    parameter OUT_RSHIFT2 =      0; // overall right shift for the second (vertical) pass
    parameter DSP_B_WIDTH =     18; // signed, output from sin/cos ROM
    parameter DSP_A_WIDTH =     25;
    parameter DSP_P_WIDTH =     48;
    parameter DEAD_CYCLES =     14;  // start next block immedaitely, or with longer pause
//    parameter OUTS_AT_ONCE =     0;  // 0: outputs with lowest latency, 1: all at once (with green)
    parameter OUTS_AT_ONCE =     1;  // 0: outputs with lowest latency, 1: all at once (with green)
    parameter TILE_PAGE_BITS =   2;  // 1 or 2  only: number of bits in tile counter (>=2 for simultaneous rotated readout, limited by red)
    
    reg              RST = 1'b1;
    reg              CLK = 1'b0;
    
    
    integer   i, n;
//    wire                        pre_busy;
    reg                         LATE = 0;
    
    wire                        pre_last_in;   // SuppressThisWarning VEditor - output only
    wire                        pre_first_out; // SuppressThisWarning VEditor - output only
    wire                        pre_last_out;  // SuppressThisWarning VEditor - output only
    wire                  [7:0] out_addr;      // SuppressThisWarning VEditor - output only
    wire                        dv;            // SuppressThisWarning VEditor - output only
    wire        [OUT_WIDTH-1:0] dout0;         // SuppressThisWarning VEditor - output only
    wire        [OUT_WIDTH-1:0] dout1;         // SuppressThisWarning VEditor - output only
    wire                        pre_busy3; // output// SuppressThisWarning VEditor - output only
    wire                        pre_last_in3; // output// SuppressThisWarning VEditor - output only
    wire                        pre_first_out_r; // output// SuppressThisWarning VEditor - output only
    wire                        pre_first_out_b; // output// SuppressThisWarning VEditor - output only
    wire                        pre_first_out_g; // output// SuppressThisWarning VEditor - output only
    wire                        pre_last_out_r; // output// SuppressThisWarning VEditor - output only
    wire                        pre_last_out_b; // output// SuppressThisWarning VEditor - output only
    wire                        pre_last_out_g; // output// SuppressThisWarning VEditor - output only
    wire                  [8:0] out_addr_r; // output[7:0] // SuppressThisWarning VEditor - output only
    wire                  [8:0] out_addr_b; // output[7:0] // SuppressThisWarning VEditor - output only
    wire                  [8:0] out_addr_g; // output[7:0] // SuppressThisWarning VEditor - output only
    wire                        dv_r; // output// SuppressThisWarning VEditor - output only
    wire                        dv_b; // output// SuppressThisWarning VEditor - output only
    wire                        dv_g; // output// SuppressThisWarning VEditor - output only
    wire        [OUT_WIDTH-1:0] dout_r; // output[24:0] signed // SuppressThisWarning VEditor - output only
    wire        [OUT_WIDTH-1:0] dout_b; // output[24:0] signed // SuppressThisWarning VEditor - output only
    wire        [OUT_WIDTH-1:0] dout_g; // output[24:0] signed // SuppressThisWarning VEditor - output only
    
//    assign  #(1)  pre_busy = pre_busy_w;
    
    always #(CLK_PERIOD/2) CLK = ~CLK;
    
    localparam  PIX_ADDR_WIDTH = 9;
//    localparam ADDR_DLY = 2;
    localparam  EXT_PIX_LATENCY =  2; // external pixel buffer a->d latency (may increase to 4 for gamma)
    localparam  TILE_SIDE = 22;
    localparam  TILE_SIZE = TILE_SIDE * TILE_SIDE;
    localparam  TILE_START= 'hc;
    localparam  TILE_END = TILE_START +  TILE_SIZE;
    
    localparam  INTILE_START = TILE_END;
    localparam  INTILE_SIZE =  'h300;
    localparam  INTILE_END =   INTILE_START + INTILE_SIZE;
     
    localparam  SGN_START =    INTILE_END;
    localparam  SGN_SIZE =     'h300;
    localparam  SGN_END =       SGN_START + SGN_SIZE;

    localparam  WND_START =    SGN_END;
    localparam  WND_SIZE =     'h300;
    localparam  WND_END =       WND_START + WND_SIZE;
    
    localparam  DTT_IN_START =  WND_END;
    localparam  DTT_IN_SIZE =  'h300;
    localparam  DTT_IN_END =    DTT_IN_START + DTT_IN_SIZE;
    
    localparam  DTT_OUT_START =  DTT_IN_END;
    localparam  DTT_OUT_SIZE =  'h300;
    localparam  DTT_OUT_END =    DTT_OUT_START + DTT_OUT_SIZE;

    localparam  DTT_ROT_START =  DTT_OUT_END;
    localparam  DTT_ROT_SIZE =  'h300;
    localparam  DTT_ROT_END =    DTT_ROT_START + DTT_ROT_SIZE; // SuppressThisWarning VEditor 

    integer java_all[0:5103]; //'h126f]; // SuppressThisWarning VEditor : assigned in $readmem() system task

    reg                   [1:0] TILE_SIZE2 =   (TILE_SIDE - 16) >> 1; // 3; // 22;
//    wire                        PIX_RE;  // SuppressThisWarning VEditor : debug only
//    wire                  [8:0] PIX_ADDR9;
//    wire                        PIX_COPY_PAGE; // copy page address // SuppressThisWarning VEditor - not yet used
//    wire    [PIXEL_WIDTH-1 : 0] PIX_D;  
    reg     [PIXEL_WIDTH-1 : 0] bayer_tiles[0:1023]; // SuppressThisWarning VEditor : assigned in $readmem() system task
    reg     [PIXEL_WIDTH-1 : 0] jav_pix_in [0:INTILE_SIZE*2-1]; 
    reg                 [3 : 0] jav_signs  [0:SGN_SIZE*2-1];    // SuppressThisWarning VEditor not yet used
    reg       [WND_WIDTH-1 : 0] jav_wnd    [0:WND_SIZE*2-1];    // SuppressThisWarning VEditor not yet used 
    reg    [DTT_IN_WIDTH - 1:0] jav_dtt_in [0:DTT_IN_SIZE*2-1]; 
    reg       [OUT_WIDTH - 1:0] jav_dtt_out[0:DTT_OUT_SIZE*2-1];
    reg       [OUT_WIDTH - 1:0] jav_dtt_rot[0:DTT_ROT_SIZE*2-1];
    reg       [SHIFT_WIDTH-1:0] jav_shifts_x [0:3*2-1];
    reg       [SHIFT_WIDTH-1:0] jav_shifts_y [0:3*2-1];
    reg                         jav_inv_check[0:3*2-1];
    reg                   [7:0] jav_top_left[0:3*2-1];
    reg                   [1:0] jav_vld_rows[0:3*2-1];
    
    integer                     offs_x, offs_y, top_left;
    reg                   [1:0] byr_index; // [0:2]; // bayer index of top-left 16x16 tile

    initial begin
//        $readmemh("input_data/mclt_dtt_all_00_x1489_y951.dat",  java_all);
        $readmemh("input_data/mclt_dtt_all_02_x1489_y951.dat",  java_all);

        $display("000c:  %h", java_all['h000c]);

        $display("01f0:  %h", java_all['h01f0]);
        $display("02f0:  %h", java_all['h02f0]);
        $display("03f0:  %h", java_all['h03f0]);

        $display("04f0:  %h", java_all['h04f0]);
        $display("05f0:  %h", java_all['h05f0]);
        $display("06f0:  %h", java_all['h06f0]);

        $display("07f0:  %h", java_all['h07f0]);
        $display("08f0:  %h", java_all['h08f0]);
        $display("09f0:  %h", java_all['h09f0]);

        $display("0af0:  %h", java_all['h0af0]);
        $display("0bf0:  %h", java_all['h0bf0]);
        $display("0cf0:  %h", java_all['h0cf0]);

        $display("0df0:  %h", java_all['h0df0]);
        $display("0ef0:  %h", java_all['h0ef0]);
        $display("0ff0:  %h", java_all['h0ff0]);

        $display("10f0:  %h", java_all['h10f0]);
        $display("11f0:  %h", java_all['h11f0]);
        $display("12f0:  %h", java_all['h12f0]);
        for (i=0; i<3; i=i+1) begin
            jav_shifts_x[0 + i] = java_all[0 + 4 * i][SHIFT_WIDTH-1:0]; 
            jav_shifts_x[3 + i] = java_all[0 + 4 * i][SHIFT_WIDTH-1:0]; 
            jav_shifts_y[0 + i] = java_all[1 + 4 * i][SHIFT_WIDTH-1:0]; 
            jav_shifts_y[3 + i] = java_all[1 + 4 * i][SHIFT_WIDTH-1:0]; 
        end

        for (i=0; i < 3; i=i+1) begin // two sets
            byr_index =            (java_all[2 + 4 * i] & 1) + ((java_all[3 + 4 * i] & 1) << 1); // bayer index of top left 16x16 tile
            offs_x=                java_all[2 + 4 * i] - java_all[2 + 4 * 2] + TILE_SIZE2;
            offs_y=                java_all[3 + 4 * i] - java_all[3 + 4 * 2] + TILE_SIZE2;
            top_left =             offs_x + TILE_SIDE * offs_y;
            jav_top_left[0 + i] =  top_left[7:0];
            jav_top_left[3 + i] =  top_left[7:0];
            jav_inv_check[0 + i] = ((i == 2)? 1'b0 : 1'b1) ^ byr_index[0] ^ byr_index[1];
            jav_inv_check[3 + i] = ((i == 2)? 1'b0 : 1'b1) ^ byr_index[0] ^ byr_index[1];
            jav_vld_rows[0 + i] =  (i == 2)? 2'h3 : ((i == 1)?{~byr_index[1],byr_index[1]}:{byr_index[1],~byr_index[1]});
            jav_vld_rows[3 + i] =  (i == 2)? 2'h3 : ((i == 1)?{~byr_index[1],byr_index[1]}:{byr_index[1],~byr_index[1]});
        end
    
        for (i=0; i < 2; i=i+1) begin // two sets
        
        end
    
        for (i=0; i<TILE_SIZE; i=i+1) begin
            bayer_tiles['h000 + i] = java_all[TILE_START+i][PIXEL_WIDTH-1 : 0]; 
            bayer_tiles['h200 + i] = java_all[TILE_START+i][PIXEL_WIDTH-1 : 0]; 
        end
        for (i=0; i<INTILE_SIZE; i=i+1) begin
            jav_pix_in[0           + i] = java_all[INTILE_START+i][PIXEL_WIDTH-1 : 0]; 
            jav_pix_in[INTILE_SIZE + i] = java_all[INTILE_START+i][PIXEL_WIDTH-1 : 0]; 
        end
        
        for (i=0; i<SGN_SIZE; i=i+1) begin
            jav_signs[            + i] = java_all[SGN_START+i][3 : 0]; 
            jav_signs[SGN_SIZE + i] =    java_all[SGN_START+i][3 : 0]; 
        end
        for (i=0; i<WND_SIZE; i=i+1) begin
            jav_wnd[            + i] = java_all[WND_START+i][WND_WIDTH-1 : 0]; 
            jav_wnd[WND_SIZE + i] =    java_all[WND_START+i][WND_WIDTH-1 : 0]; 
        end
        for (i=0; i<DTT_IN_SIZE; i=i+1) begin
            jav_dtt_in[            + i] = java_all[DTT_IN_START+i][DTT_IN_WIDTH-1 : 0]; 
            jav_dtt_in[DTT_IN_SIZE + i] = java_all[DTT_IN_START+i][DTT_IN_WIDTH-1 : 0]; 
        end
        for (i=0; i<DTT_OUT_SIZE; i=i+1) begin
            jav_dtt_out[            + i] =  java_all[DTT_OUT_START+i][OUT_WIDTH-1 : 0]; 
            jav_dtt_out[DTT_OUT_SIZE + i] = java_all[DTT_OUT_START+i][OUT_WIDTH-1 : 0]; 
        end
        for (i=0; i<DTT_ROT_SIZE; i=i+1) begin
            jav_dtt_rot[            + i] =  java_all[DTT_ROT_START+i][OUT_WIDTH-1 : 0]; 
            jav_dtt_rot[DTT_ROT_SIZE + i] = java_all[DTT_ROT_START+i][OUT_WIDTH-1 : 0]; 
        end
        
    end

    reg       START;
    
    reg       PRE_BUSY;
    
    reg [7:0] in_cntr;
    reg       in_run;
    wire      pre_last_count = (in_cntr == 'hfe);
    reg       last_count_r;
//    wire      pre_last_128 = (in_cntr[6:0] == 'h7e);
//    reg       last_128_r;
//    wire      start = START | (last_128_r  && ! in_cntr[8]);
//    reg       PAGE;   // full page, 192 clocks
    integer       PAGE;   // full page, 192 clocks
//    reg   [2:0] SUB_PAGE; // single color page
//    reg         PIX_PAGE;
//    wire  [9:0] PIX_ADDR10 = {PIX_PAGE,PIX_ADDR9};  // SuppressThisWarning VEditor debug output
          
    always @ (posedge CLK) begin
        last_count_r <= pre_last_count;
//        last_128_r <=   pre_last_128;
        
        if      (RST)          in_run <= 0;
        else if (START)        in_run <= 1;
        else if (last_count_r) in_run <= 0;
        
        if (!in_run) in_cntr <= 0;
        else         in_cntr <= in_cntr + 1;
        
        if      (RST)            PAGE <= 0;
//        else if (pre_last_count) PAGE <= PAGE + 1;
        else if (in_cntr == 'hf0) PAGE <= PAGE + 1;
        
//        if      (RST)            SUB_PAGE <= 0;
//        else if (pre_last_128)   SUB_PAGE <= SUB_PAGE + 1;
        
//        if (PIX_COPY_PAGE) PIX_PAGE <= PAGE;
        
        if      (RST)             PRE_BUSY <= 0;
        else if (START)           PRE_BUSY <= 1;
        else if (in_cntr == 'hf0) PRE_BUSY <= 0;
        
        
        
    end
    
    initial begin
        $dumpfile(fstname);
        $dumpvars(0,mclt_test_06); // SuppressThisWarning VEditor
        #100;
        START =  0;
        LATE = 0;
        RST = 0;
        #100;
        repeat (10) @(posedge CLK);
        #1 START = 1;
        @(posedge CLK)
        #1 START = 0;
        for (n = 0; n < 1; n = n+1) begin
            if (n >= 1) LATE = 1;
//            if (n >= 0) LATE = 1;
//            while (!in_cntr[8]) begin
            while (!in_cntr[7]) begin
                @(posedge CLK);
                #1;
            end
//PRE_BUSY            
//            while (pre_busy || LATE) begin
///            while (pre_busy3 || LATE) begin
///                if (!pre_busy3) LATE = 0;
            while (PRE_BUSY || LATE) begin
                if (!PRE_BUSY) LATE = 0;
                @(posedge CLK);
                #1;
            end
            #1 START = 1;
            @(posedge CLK)
            #1 START = 0;
        end
        repeat (1024) @(posedge CLK);
        $finish; 
        
    end

    integer n1, cntr1, diff1, p1;// SuppressThisWarning VEditor : assigned in $readmem() system task
    wire               [7:0] wnd_a_w = mclt16x16_bayer3_i.mclt_bayer_fold_rgb_i.wnd_a_w;
    wire               [2:0] pix_page= 3 * n1 + p1;
    wire               [2:0] pix_page_d;
    wire              [10:0] jav_pix_in_now_a = {pix_page_d, wnd_a_w};
    wire [PIXEL_WIDTH-1 : 0] jav_pix_in_now =  cntr1[7]?{PIXEL_WIDTH{1'bz}}:jav_pix_in[jav_pix_in_now_a];
    wire [PIXEL_WIDTH-1 : 0] jav_pix_in_now_d;
   dly_var #(
        .WIDTH(PIXEL_WIDTH),
        .DLY_WIDTH(4)
    ) dly_jav_pix_in_now_d_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h4),          // input[3:0] 
        .din  (jav_pix_in_now),      // input[0:0] 
        .dout (jav_pix_in_now_d)     // output[0:0] 
    );
    
   dly_var #(
        .WIDTH(3),
        .DLY_WIDTH(4)
    ) dly_jav_pix_page_d_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h0), // 7),          // input[3:0] 
        .din  (pix_page),      // input[0:0] 
        .dout (pix_page_d)     // output[0:0] 
    );

    initial begin
        while (RST) @(negedge CLK);
        for (n1 = 0; n1 < 2; n1 = n1+1) begin
            while (!mclt16x16_bayer3_i.mclt_bayer_fold_rgb_i.run_r[0] ||
                 (mclt16x16_bayer3_i.mclt_bayer_fold_rgb_i.in_cntr != 2)) begin
                @(negedge CLK);
            end
            for (p1 = 0; p1 <3; p1=p1+1) begin
                for (cntr1 = 0; cntr1 < ((p1 > 1)?128:64); cntr1 = cntr1 + 1) begin
                    diff1 = PIX_D3 - jav_pix_in_now_d; // java_fold_index[cntr1];
                    @(negedge CLK);
                end
            end
            
        end
    end


//Compare DTT inputs


    integer n4, cntr4, diff4,p4; // SuppressThisWarning VEditor : assigned in $readmem() system task
    wire [DTT_IN_WIDTH-1:0] data_dtt_in = mclt16x16_bayer3_i.data_dtt_in;
    wire              [2:0] page4 = 3 * n4 + p4;
    wire             [10:0] java_dtt_in_addr = (p4>1)?
                           {page4, 1'b0, cntr4[0],cntr4[6:1]} :
                           {page4, 1'b0, 1'b0,    cntr4[5:0]};
    wire [DTT_IN_WIDTH-1:0] java_data_dtt_in = jav_dtt_in[java_dtt_in_addr]; // java_dtt_in0[{cntr4[1:0],cntr4[7:2]}]  
    initial begin
        while (RST) @(negedge CLK);
        for (n4 = 0; n4 < 2; n4 = n4+1) begin
`ifdef DSP_ACCUM_FOLD        
            while ((mclt16x16_bayer3_i.dtt_in_precntr != 1) ||!mclt16x16_bayer3_i.dtt_prewe) begin
                @(negedge CLK);
            end
`else
            while ((mclt16x16_bayer3_i.dtt_in_precntr != 0) ||!mclt16x16_bayer3_i.dtt_prewe) begin
                @(negedge CLK);
            end
`endif            
            for (p4 = 0; p4 < 3; p4=p4+1) begin
                for (cntr4 = 0; cntr4 < ((p4 > 1)?128:64); cntr4 = cntr4 + 1) begin
                    #1;
                    diff4 = data_dtt_in - java_data_dtt_in;
                    @(negedge CLK);
                end
            end
        end
    end


    integer n5, cntr5, diff5,p5; // SuppressThisWarning VEditor : assigned in $readmem() system task
    wire              [2:0] page5 = 3 * n5 + p5;
//    wire             [10:0] java_dtt_r_addr = (p5>1)?
//                           {page5,  1'b0, cntr5[6:0]} :
//                           {page5,  2'b0, cntr5[5:0]};
    wire             [10:0] java_dtt_r_addr = {page5,  1'b0, cntr5[6:0]};
    wire [DTT_IN_WIDTH-1:0] dtt_r_data = mclt16x16_bayer3_i.dtt_r_data;
    wire [DTT_IN_WIDTH-1:0] java_dtt_r_data =  jav_dtt_in[java_dtt_r_addr]; // java_dtt_in0[cntr5[7:0]];
    
    wire                           dtt_r_regen = mclt16x16_bayer3_i.dtt_r_regen;
    reg                            dtt_r_dv; // SuppressThisWarning VEditor just for simulation
    always @ (posedge CLK) begin
        if (RST) dtt_r_dv <= 0;
        else     dtt_r_dv <= dtt_r_regen;
    end
    
      
    initial begin
        while (RST) @(negedge CLK);
        for (n5 = 0; n5 < 6; n5 = n5+1) begin
            while ((!dtt_r_dv) || (mclt16x16_bayer3_i.dtt_r_cntr[6:0] != 2)) begin
                @(negedge CLK);
            end
            for (p5 = 0; p5 < 3; p5=p5+1) begin
                for (cntr5 = 0; cntr5 < ((p5 > 1)?128:64); cntr5 = cntr5 + 1) begin
                    #1;
                    diff5 = dtt_r_data - java_dtt_r_data;
                    @(negedge CLK);
                end
            end
        end
    end

/*
    integer n50, cntr50, diff50; // SuppressThisWarning VEditor : assigned in $readmem() system task
    wire [DTT_IN_WIDTH-1:0] dtt_r_data0 = mclt16x16_bayer_i.dtt_r_data;
    wire [DTT_IN_WIDTH-1:0] java_dtt_r_data0 =  jav_dtt_in[{n50[2:0], 1'b0, cntr50[6:0]}]; // java_dtt_in0[cntr5[7:0]];
    
    wire                           dtt_r_regen0 = mclt16x16_bayer_i.dtt_r_regen;
    reg                            dtt_r_dv0; // SuppressThisWarning VEditor just for simulation
    always @ (posedge CLK) begin
        if (RST) dtt_r_dv0 <= 0;
        else     dtt_r_dv0 <= dtt_r_regen0;
    end
    
      
    initial begin
        while (RST) @(negedge CLK);
        for (n50 = 0; n50 < 6; n50 = n50+1) begin
            while ((!dtt_r_dv0) || (mclt16x16_bayer_i.dtt_r_cntr[6:0] != 2)) begin
                @(negedge CLK);
            end
            for (cntr50 = 0; cntr50 < 128; cntr50 = cntr50 + 1) begin
                #1;
                diff50 = dtt_r_data0 - java_dtt_r_data0;
                @(negedge CLK);
            end
        end
    end
*/




    integer n6, cntr6, diff6r, diff6b, diff6g; // SuppressThisWarning VEditor : assigned in $readmem() system task
    wire [TILE_PAGE_BITS+5:0] dtt_rd_ra_r =    mclt16x16_bayer3_i.dtt_rd_ra_r;
    wire [TILE_PAGE_BITS+5:0] dtt_rd_ra_b =    mclt16x16_bayer3_i.dtt_rd_ra_b;
    wire [7:0] dtt_rd_ra_g =    mclt16x16_bayer3_i.dtt_rd_ra_g;
    wire [1:0] dtt_rd_regen_r = mclt16x16_bayer3_i.dtt_rd_regen_r;
    wire [1:0] dtt_rd_regen_b = mclt16x16_bayer3_i.dtt_rd_regen_b;
    wire [1:0] dtt_rd_regen_g = mclt16x16_bayer3_i.dtt_rd_regen_g;
    wire [DTT_IN_WIDTH-1:0] dtt_rd_data_r = mclt16x16_bayer3_i.dtt_rd_data_r;
    wire [DTT_IN_WIDTH-1:0] dtt_rd_data_b = mclt16x16_bayer3_i.dtt_rd_data_b;
    wire [DTT_IN_WIDTH-1:0] dtt_rd_data_g = mclt16x16_bayer3_i.dtt_rd_data_g;
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_r=jav_dtt_out['h300*dtt_rd_ra_r[6] + 'h000 + dtt_rd_ra_r[5:0]];
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_b=jav_dtt_out['h300*dtt_rd_ra_b[6] + 'h100 + dtt_rd_ra_b[5:0]];
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_g=jav_dtt_out['h300*dtt_rd_ra_g[7] + 'h200 + dtt_rd_ra_g[6:0]];
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_rd;
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_bd;
    wire [DTT_IN_WIDTH-1:0] java_dtt_rd_data_gd;
    reg       dtt_rd_regen_rv;
    reg       dtt_rd_regen_bv;
    reg       dtt_rd_regen_gv;
    
    always @ (posedge CLK) begin
        dtt_rd_regen_rv <= dtt_rd_regen_r[1];
        dtt_rd_regen_bv <= dtt_rd_regen_b[1];
        dtt_rd_regen_gv <= dtt_rd_regen_g[1];
        diff6r <= dtt_rd_regen_rv? (dtt_rd_data_r - java_dtt_rd_data_rd) : 'bz;
        diff6b <= dtt_rd_regen_bv? (dtt_rd_data_b - java_dtt_rd_data_bd) : 'bz;
        diff6g <= dtt_rd_regen_gv? (dtt_rd_data_g - java_dtt_rd_data_gd) : 'bz;
    end
    
    
   dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_java_dtt_rd_data_rd_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (java_dtt_rd_data_r),      // input[0:0] 
        .dout (java_dtt_rd_data_rd)     // output[0:0] 
    );

   dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_java_dtt_rd_data_bd_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (java_dtt_rd_data_b),      // input[0:0] 
        .dout (java_dtt_rd_data_bd)     // output[0:0] 
    );

   dly_var #(
        .WIDTH(DTT_IN_WIDTH),
        .DLY_WIDTH(4)
    ) dly_java_dtt_rd_data_gd_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (java_dtt_rd_data_g),      // input[0:0] 
        .dout (java_dtt_rd_data_gd)     // output[0:0] 
    );
    

//dout_r, dout_b, dout_g
    integer n7r, n7b, n7g;
    reg [7:0] cntr7r, cntr7b, cntr7g;
    always @ (posedge CLK) begin
        if      (RST)           n7r <= -1; else if (pre_first_out_r) n7r <= n7r + 1;
        if (pre_first_out_r) cntr7r <= 0; else if (dv_r)            cntr7r <= cntr7r + 1; 

        if      (RST)           n7b <= -1; else if (pre_first_out_b) n7b <= n7b + 1;
        if (pre_first_out_b) cntr7b <= 0; else if (dv_b)            cntr7b <= cntr7b + 1; 

        if      (RST)           n7g <= -1; else if (pre_first_out_g) n7g <= n7g + 1;
        if (pre_first_out_g) cntr7g <= 0; else if (dv_g)            cntr7g <= cntr7g + 1; 
    end

    integer diff7r, diff7b, diff7g; // SuppressThisWarning VEditor : assigned in $readmem() system task
///    wire [OUT_WIDTH-1:0] java_dout_r0 = jav_dtt_rot['h300*out_addr_r[8] + 'h000 + {out_addr_r[7:6], out_addr_r[2:0], out_addr_r[5:3]}];
///    wire [OUT_WIDTH-1:0] java_dout_b0 = jav_dtt_rot['h300*out_addr_b[8] + 'h100 + {out_addr_b[7:6], out_addr_b[2:0], out_addr_b[5:3]}];
///    wire [OUT_WIDTH-1:0] java_dout_g0 = jav_dtt_rot['h300*out_addr_g[8] + 'h200 + {out_addr_g[7:6], out_addr_g[2:0], out_addr_g[5:3]}];
    wire [OUT_WIDTH-1:0] java_dout_r = jav_dtt_rot['h300*n7r + 'h000 + {cntr7r[1:0], cntr7r[7:2]}];
    wire [OUT_WIDTH-1:0] java_dout_b = jav_dtt_rot['h300*n7b + 'h100 + {cntr7b[1:0], cntr7b[7:2]}];
    wire [OUT_WIDTH-1:0] java_dout_g = jav_dtt_rot['h300*n7g + 'h200 + {cntr7g[1:0], cntr7g[7:2]}];
    
    always @ (posedge CLK) begin
        diff7r <= dv_r? (dout_r - java_dout_r) : 'bz;
        diff7b <= dv_b? (dout_b - java_dout_b) : 'bz;
        diff7g <= dv_g? (dout_g - java_dout_g) : 'bz;
    end

/*
    mclt16x16_bayer #(
        .SHIFT_WIDTH     (SHIFT_WIDTH),
        .PIX_ADDR_WIDTH  (PIX_ADDR_WIDTH),
        .EXT_PIX_LATENCY (EXT_PIX_LATENCY), // 2), // external pixel buffer a->d latency (may increase to 4 for gamma)
        .COORD_WIDTH     (COORD_WIDTH),
        .PIXEL_WIDTH     (PIXEL_WIDTH),
        .WND_WIDTH       (WND_WIDTH),
        .OUT_WIDTH       (OUT_WIDTH),
        .DTT_IN_WIDTH    (DTT_IN_WIDTH),
        .TRANSPOSE_WIDTH (TRANSPOSE_WIDTH),
        .OUT_RSHIFT      (OUT_RSHIFT1),
        .OUT_RSHIFT2     (OUT_RSHIFT2),
        .DSP_B_WIDTH     (DSP_B_WIDTH),
        .DSP_A_WIDTH     (DSP_A_WIDTH),
        .DSP_P_WIDTH     (DSP_P_WIDTH),
        .DEAD_CYCLES     (DEAD_CYCLES)
    ) mclt16x16_bayer_i (
        .clk           (CLK),                     // input
        .rst           (RST),                     // input
        .start         (start),                   // input
        .tile_size     (TILE_SIZE2),              // input[1:0] 
        .inv_checker   (jav_inv_check[SUB_PAGE]), // INV_CHECKER), // input
        .top_left      (jav_top_left[SUB_PAGE]),  // TOP_LEFT),    // input[7:0] 
        .valid_rows    (jav_vld_rows[SUB_PAGE]),  // VALID_ROWS),  // input[1:0] 
        .x_shft        (jav_shifts_x[SUB_PAGE]),  //CLT_SHIFT_X), // input[6:0] 
        .y_shft        (jav_shifts_y[SUB_PAGE]),  //CLT_SHIFT_Y), // input[6:0] 
        .pix_addr      (PIX_ADDR9),               // output[8:0] 
        .pix_re        (PIX_RE),                  // output
        .pix_page      (PIX_COPY_PAGE),           // output
        .pix_d         (PIX_D),                   // input[15:0]
        .pre_busy      (pre_busy),                // output
        .pre_last_in   (pre_last_in),             // output
        .pre_first_out (pre_first_out),           // output
        .pre_last_out  (pre_last_out),            // output
        .out_addr      (out_addr),                // output[7:0] 
        .dv            (dv),                      // output
        .dout0         (dout0),                   // output[24:0] signed 
        .dout1         (dout1)                    // output[24:0] signed 
         
    );

   dly_var #(
        .WIDTH(PIXEL_WIDTH),
        .DLY_WIDTH(4)
    ) dly_pix_dly_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (PIX_RE?bayer_tiles[PIX_ADDR10]:{PIXEL_WIDTH{1'bz}}),      // input[0:0] 
        .dout (PIX_D)     // output[0:0] 
    );

*/

    wire                        PIX_RE3;  // SuppressThisWarning VEditor : debug only
    wire                  [8:0] PIX_ADDR93;
    reg    [TILE_PAGE_BITS-1:0] PIX_PAGE3;
    wire                  [9:0] PIX_ADDR103 = {PIX_PAGE3,PIX_ADDR93};  // SuppressThisWarning VEditor debug output
    
    wire                        PIX_COPY_PAGE3; // copy page address // SuppressThisWarning VEditor - not yet used
    wire    [PIXEL_WIDTH-1 : 0] PIX_D3;
    reg                         start3;  
    reg  [TILE_PAGE_BITS-1 : 0] page3; // 1/2-nd bayer tile
    reg                         pre_run;
    reg                   [1:0] pre_run_cntr;
    wire                  [2:0] color_page = pre_run_cntr + 3 * page3; // SuppressThisWarning VEditor - VDT bug (used as index)
    reg                         pending;
    always @ (posedge CLK) begin
        if (START)                  page3 <= PAGE[TILE_PAGE_BITS-1:0]; // (SUB_PAGE > 2);
        
        if (RST)                    pre_run <= 0;
        else if (START)             pre_run <= 1;
        else if (pre_run_cntr == 2) pre_run <= 0;
        
        if (!pre_run) pre_run_cntr <= 0;
        else          pre_run_cntr <= pre_run_cntr + 1;
        
        if (PIX_COPY_PAGE3) PIX_PAGE3 <= page3;
        
        if (RST)                    pending <= 0;
        else if (pre_run_cntr == 1) pending <= 1;
        else if (!pre_busy3)        pending <= 0;
        
        start3 <=                   pending && !pre_busy3; //  (pre_run_cntr == 2);
    
    end 

    mclt16x16_bayer3 #(
        .SHIFT_WIDTH     (SHIFT_WIDTH),
        .PIX_ADDR_WIDTH  (PIX_ADDR_WIDTH),
        .EXT_PIX_LATENCY (EXT_PIX_LATENCY), // 2), // external pixel buffer a->d latency (may increase to 4 for gamma)
        .COORD_WIDTH     (COORD_WIDTH),
        .PIXEL_WIDTH     (PIXEL_WIDTH),
        .WND_WIDTH       (WND_WIDTH),
        .OUT_WIDTH       (OUT_WIDTH),
        .DTT_IN_WIDTH    (DTT_IN_WIDTH),
        .TRANSPOSE_WIDTH (TRANSPOSE_WIDTH),
        .OUT_RSHIFT1     (OUT_RSHIFT1),
        .OUT_RSHIFT2     (OUT_RSHIFT2),
        .DSP_B_WIDTH     (DSP_B_WIDTH),
        .DSP_A_WIDTH     (DSP_A_WIDTH),
        .DSP_P_WIDTH     (DSP_P_WIDTH),
        .DEAD_CYCLES     (DEAD_CYCLES),
        .OUTS_AT_ONCE    (OUTS_AT_ONCE),
        .TILE_PAGE_BITS  (TILE_PAGE_BITS)
    ) mclt16x16_bayer3_i (
        .clk            (CLK),                        // input
        .rst            (RST),                        // input
        .start          (start3),                     // input
        .page           (page3),                      // input
        .tile_size      (TILE_SIZE2),                 // input[1:0] 
        .color_wa       (pre_run_cntr),               // input[1:0] 
        .inv_checker    (jav_inv_check[color_page]),  // input
        .top_left       (jav_top_left[color_page]),   // TOP_LEFT),    // input[7:0] 
        .valid_odd      (jav_vld_rows[color_page][1]),// VALID_ROWS),  // input[1:0] 
        .x_shft         (jav_shifts_x[color_page]),   //CLT_SHIFT_X), // input[6:0] 
        .y_shft         (jav_shifts_y[color_page]),   //CLT_SHIFT_Y), // input[6:0] 
        .set_inv_checker(pre_run), // input
        .set_top_left   (pre_run), // input
        .set_valid_odd  (pre_run), // input
        .set_x_shft     (pre_run), // input
        .set_y_shft     (pre_run), // input
        .pix_addr       (PIX_ADDR93),               // output[8:0] 
        .pix_re         (PIX_RE3),                  // output
        .pix_page       (PIX_COPY_PAGE3),           // output
        .pix_d          (PIX_D3),                   // input[15:0]
        .pre_busy       (pre_busy3), // output
        .pre_last_in    (pre_last_in3), // output
        .pre_first_out_r(pre_first_out_r), // output
        .pre_first_out_b(pre_first_out_b), // output
        .pre_first_out_g(pre_first_out_g), // output
        .pre_last_out_r (pre_last_out_r), // output
        .pre_last_out_b (pre_last_out_b), // output
        .pre_last_out_g (pre_last_out_g), // output
        .out_addr_r     (out_addr_r), // output[7:0] 
        .out_addr_b     (out_addr_b), // output[7:0] 
        .out_addr_g     (out_addr_g), // output[7:0] 
        .dv_r           (dv_r), // output
        .dv_b           (dv_b), // output
        .dv_g           (dv_g), // output
        .dout_r         (dout_r), // output[24:0] signed 
        .dout_b         (dout_b), // output[24:0] signed 
        .dout_g         (dout_g) // output[24:0] signed 
    );

   dly_var #(
        .WIDTH(PIXEL_WIDTH),
        .DLY_WIDTH(4)
    ) dly_pix_dly3_i (
        .clk  (CLK),           // input
        .rst  (RST),           // input
        .dly  (4'h1),          // input[3:0] 
        .din  (PIX_RE3?bayer_tiles[PIX_ADDR103]:{PIXEL_WIDTH{1'bz}}),      // input[0:0] 
        .dout (PIX_D3)     // output[0:0] 
    );




endmodule
