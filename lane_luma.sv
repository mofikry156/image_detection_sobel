module lane_luma (

	input logic i_clk,i_rst_n,
	input logic[23:0] i_rgb,
	output logic[11:0] o_luma
	);

	logic [7:0] r,g,b;
	assign r =  i_rgb [23:16];
	assign g = i_rgb[15:8];
	assign b = i_rgb[7:0] ;

	always_ff @(posedge i_clk or negedge i_rst_n) begin : proc_o_luma
		if(~i_rst_n) begin
			o_luma <= 0;
		end else begin
			o_luma <= 3'd5*r+4'd9*g+2'd2*b;
		end
	end

endmodule : lane_luma