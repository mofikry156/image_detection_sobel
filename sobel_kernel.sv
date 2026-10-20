module sobel_kernel (

	input logic i_clk,i_rst_n,
	input logic [11:0] i_data,
	output logic [23:0] o_data_out,
	input logic i_write_en
	);

	logic [11:0] rb,rc,ru,cb,cc,cu,lb,lc,lu;  /* r stands for (right) , l(left) c (center) */
	logic [27:0] o_g_horizontal,o_g_vertical;
   logic [7:0] lum;
	logic [28:0] g_total;     // Gx² + Gy², up to 532,684,800
	logic [15:0] g_sum;       // g_total / 8192, up to 65,026
	logic [12:0] g_limit;     // clamped ROM address (0 to 8191)
	assign rb = i_data;


	lane_linemem lane_linemem_1 (

		    .i_clk(i_clk),
    		.i_rst_n(i_rst_n),
    		.i_data_in(rb),
    		.i_write_en(i_write_en),
    		.o_data(rc)
		);

		lane_linemem lane_linemem_0 (

		    .i_clk(i_clk),
    		.i_rst_n(i_rst_n),
    		.i_data_in(rc),
    		.i_write_en(i_write_en),
    		.o_data(ru)
		);


		always @(posedge i_clk or negedge i_rst_n) begin 
			if(!i_rst_n) begin
				 cb<= 'b0;
				 cc<= 'b0;
				 cu<= 'b0;
				 lb<= 'b0;
				 lc<= 'b0;
				 lu<= 'b0;
			end else begin
				 cb<= rb;
				 cc<= rc;
				 cu<= ru;
				 lb<= cb;
				 lc<= cc;
				 lu<= cu;
			end
		end
		
		
		g_matrix g_matrix_horizontal (
		
				.i_p1a(ru),
				.i_p2(rc),
				.i_p1b(rb),    
				.i_m1a(lu),
				.i_m2(lc),
				.i_m1b(lb),   
				.o_g_matrix(o_g_horizontal),
				.i_clk(i_clk),
				.i_rst_n(i_rst_n)
		
		
		);
		
				g_matrix g_matrix_vertical (
		
				.i_p1a(lu),
				.i_p2(cu),
				.i_p1b(ru),
				.i_m1a(lb),
				.i_m2(cb),
				.i_m1b(rb),
				.o_g_matrix(o_g_vertical),
				.i_clk(i_clk),
				.i_rst_n(i_rst_n)
		
		
		);
		assign g_total = o_g_vertical + o_g_horizontal;
		
		always_ff @(posedge i_clk,negedge i_rst_n)
			begin
			if(!i_rst_n)
			begin
			g_sum<='b0;
			g_limit<='b0;
			end
				else
				begin
				 g_sum   <= g_total[28:13];                     // divide by 8192
					g_limit <= (g_sum > 16'd8191) ? 13'h1FFF: g_sum[12:0];   // fits: use as is       // too big: clamp
																			
				
			end
			end
			
			rom rom_1 (
			.clock(i_clk),
			.address(g_limit),
			.q(lum)
			);
			
			assign   o_data_out = {lum , lum , lum};

endmodule