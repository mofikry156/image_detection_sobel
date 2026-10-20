`timescale 1ns/1ps

module tb();

    logic        i_clk;
    logic        i_rst_n;
    logic [11:0] i_data_in;
    logic        i_write_en;
    logic [11:0] o_data;
    logic        o_valid;
    integer      i;

    lane_linemem #(.width(24), .depth(100)) u_lane_linemem (.*);

    // clock: 10 ns period
    initial i_clk = 1'b0;
    always #5 i_clk = ~i_clk;

    initial begin
        // reset (active low)
        i_rst_n    = 1'b0;
        i_write_en = 1'b0;
        i_data_in  = '0;
        repeat (5) @(negedge i_clk);
        i_rst_n    = 1'b1;

        // stream pixels, one per clock
        @(negedge i_clk);
        i_write_en = 1'b1;
        for (i = 0; i < 300; i++) begin
            i_data_in = i;
            @(negedge i_clk);
        end

        i_write_en = 1'b0;
        repeat (5) @(negedge i_clk);
        $finish;
    end

endmodule : tb