module lane_sync #(
    parameter DELAY = 7
)(
    input  logic i_clk,
    input  logic i_vs, i_hs, i_de,
    output logic o_vs, o_hs, o_de,       // delayed by DELAY clocks
    output logic o_de_1                  // delayed by 1 clock (first box)
);

    logic [DELAY-1:0] vs_d, hs_d, de_d;

    always_ff @(posedge i_clk) begin
        vs_d <= {vs_d[DELAY-2:0], i_vs};
        hs_d <= {hs_d[DELAY-2:0], i_hs};
        de_d <= {de_d[DELAY-2:0], i_de};
    end

    assign o_vs   = vs_d[DELAY-1];
    assign o_hs   = hs_d[DELAY-1];
    assign o_de   = de_d[DELAY-1];       // last box = 7 clocks
    assign o_de_1 = de_d[0];             // first box = 1 clock

endmodule : lane_sync