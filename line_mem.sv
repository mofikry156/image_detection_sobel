module lane_linemem #(
    parameter width = 12,
    parameter depth = 1280
)(
    input  logic             i_clk,
    input  logic             i_rst_n,
    input  logic [width-1:0] i_data_in,
    input  logic             i_write_en,
    output logic [width-1:0] o_data
);

    logic [width-1:0]         mem [0:depth-1];
    logic [$clog2(depth)-1:0] write_ptr, read_ptr;
	 
	 initial begin
    for (int j = 0; j < depth; j++)
        mem[j] = '0;
					end

    always_ff @(posedge i_clk) begin
        if (i_write_en) begin
            o_data         <= mem[read_ptr];
            mem[write_ptr] <= i_data_in;
        end
    end

    // Pointers: async reset, active low
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            write_ptr <= '0;
            read_ptr  <= 1;
        end
        else if (i_write_en) begin
            write_ptr <= read_ptr;
            if (read_ptr == depth - 1)
                read_ptr <= '0;
            else
                read_ptr <= read_ptr + 1'b1;
        end
    end

endmodule : lane_linemem