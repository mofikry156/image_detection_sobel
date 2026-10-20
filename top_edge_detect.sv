

module lane  (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [2:0]  enable_in,           // unused (slide switches)
    // video in
    input  logic        vs_in, hs_in, de_in,
    input  logic [7:0]  r_in, g_in, b_in,
    // video out
    output logic        vs_out, hs_out, de_out,
    output logic [7:0]  r_out, g_out, b_out,
    // other
    output logic        clk_o,
    output logic [2:0]  led
);

    logic [23:0] rgb_in, sobel_out, rgb_out;
    logic [11:0] luma;
    logic        w_en;                       
    assign rgb_in = {r_in, g_in, b_in};

    lane_sync #(.DELAY(7)) u_sync (
        .i_clk  (clk),
        .i_vs   (vs_in),
        .i_hs   (hs_in),
        .i_de   (de_in),
        .o_vs   (vs_out),
        .o_hs   (hs_out),
        .o_de   (de_out),                    // 7 clocks
        .o_de_1 (w_en)                       // 1 clock
    );

    lane_luma u_luma (
        .i_clk (clk),
        .i_rgb (rgb_in),
        .o_luma   (luma),
        .i_rst_n(reset_n)                        
    );

    sobel_kernel u_sobel (
        .i_clk      (clk),
        .i_rst_n    (reset_n),
        .i_data     (luma),
        .i_write_en (w_en),
        .o_data_out (sobel_out)
    );

    assign rgb_out = de_out ? sobel_out : 24'h000000;

    assign r_out = rgb_out[23:16];
    assign g_out = rgb_out[15:8];
    assign b_out = rgb_out[7:0];

    assign clk_o = clk;
    assign led   = 3'b000;

endmodule : lane 