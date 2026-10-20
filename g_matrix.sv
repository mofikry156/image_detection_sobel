module g_matrix (
	input logic [11:0] i_p1a,i_p2,i_p1b,i_m1a,i_m2,i_m1b,
	output logic [27:0] o_g_matrix,
	input logic i_clk,i_rst_n
);


logic signed [14:0] sum;

always @(posedge i_clk or negedge i_rst_n)
begin
	if(~i_rst_n) begin
		sum <= 'b0;
		o_g_matrix <= 'b0;
	end else begin
		 sum <= (i_p1a + {i_p2, 1'b0} + i_p1b) - (i_m1a + {i_m2, 1'b0}  + i_m1b);
		 o_g_matrix <= sum*sum;

	end
end

endmodule
