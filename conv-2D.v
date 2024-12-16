module conv_2D(s_ready, clk, reset, done, data_in, data_out, s_valid, m_ready, s_last, m_last);
	parameter X=5, H=3;
	input clk, reset, s_valid, m_ready, s_last;
	output reg done, s_ready, m_last;
	input [7:0] data_in;
	output reg [31:0] data_out;	
	reg wr_en_h ,wr_en_x, wr_en_y, clear_acc;
	reg [13:0] addr_x;
	reg [13:0] addr_y;
	reg [7:0] addr_h;
	reg done1;
	reg [3:0] state;
	reg [15:0] data_out1,f;	
	reg [7:0] data_in1;
	reg [7:0] data_out_x;
		
	always @(*) begin		
		if (s_ready && s_valid) 
			data_in1 = data_in;
		else 
			data_in1 = 0;
	end
	
	assign data_out[15:0] = data_out1[15:0];
	assign data_out[31:16] = 0;

	datapath d(clk, data_in1, addr_x, wr_en_x, addr_h, wr_en_h, addr_y, wr_en_y, clear_acc, data_out1, f, data_out_x, m_ready);
	ctrlpath #(5, 3) c(clk, m_last, reset, addr_x, wr_en_x, addr_h, wr_en_h, clear_acc, addr_y, wr_en_y, done, s_valid, state, m_ready, s_ready);

endmodule

module memory(clk, data_in, data_out, addr, wr_en, m_ready);
	parameter WIDTH=16, SIZE=64, LOGSIZE=6;
	input [WIDTH-1:0] data_in;
	output reg [WIDTH-1:0] data_out;
	input [LOGSIZE-1:0] addr;
	input clk, wr_en, m_ready;
	reg [WIDTH-1:0] mem [SIZE-1:0];

	always @(posedge clk) begin
		if(m_ready)
			data_out <= mem[addr];
		
		if (wr_en)
			mem[addr] <= data_in;
	end
endmodule

module datapath(clk, data_in, addr_x, wr_en_x, addr_h, wr_en_h, addr_y, wr_en_y, clear_acc, data_out, f, data_out_x, m_ready);
	input clk, m_ready;
	input clear_acc, wr_en_h, wr_en_x, wr_en_y;
	input [7:0] data_in;
	input [7:0] addr_h;
	input [13:0] addr_x;
	input [13:0] addr_y;
	output reg [15:0] data_out, f;
	reg [15:0] mul_out, add_r;
	reg [7:0] data_out_h;
	output reg [7:0] data_out_x;

	memory #(8, 16384, 14) mem_x(clk, data_in, data_out_x, addr_x, wr_en_x, m_ready);
	memory #(8, 256, 8) mem_h(clk, data_in, data_out_h, addr_h, wr_en_h, m_ready);
	memory #(16, 16384, 14) mem_y(clk, f, data_out, addr_y, wr_en_y, m_ready);

    // MAC
	always @(posedge clk) begin
		if (clear_acc) 
			f <= 0;
		else 
			f <= add_r;
	end

	always @(*) begin
		mul_out = data_out_h * data_out_x;
		add_r = f + mul_out;
	end

endmodule

module ctrlpath(clk, last, reset, addr_x, wr_en_x, addr_h, wr_en_h, clear_acc, addr_y, wr_en_y, done, s_valid, state, m_ready, s_ready);
	parameter X=10, H=3;
	input clk, reset, s_valid, m_ready;
	output reg [7:0] addr_h;
	reg load_h, load_x, start;
	output reg [13:0] addr_x;
	reg [13:0] addr_xjump;
	output reg [13:0] addr_y;
	output reg wr_en_x, wr_en_h, clear_acc, wr_en_y, last;
	output reg done, s_ready;
	reg [3:0] next_state;
	output reg [3:0] state;
	reg state1_done, state3_isone, state2_done, state3_jump, state3_donefinal, state5_done, state53_done;

	always @(posedge clk) begin
		if (reset)
			state <= 0;
		else        
			state <= next_state;
	end

	always @(posedge clk) begin
		if (reset)
			done <= 0;
		else if (state == 6 || state == 7)
			done <= 1;
		else
			done <= 0;
	end

	always @(posedge clk) begin
		if (reset) 
			addr_h <= 0;
		else if (state3_donefinal == 0)
			addr_h <= addr_h + 1;
		else if (state3_isone == 1 && state != 5)
			addr_h <= addr_h;
		else if (state1_done == 0)
			addr_h <= addr_h - 1;
		else if (load_h == 1)
			addr_h <= (H*H) - 1;
		else 
			addr_h <= 0;
	end

	always @(posedge clk) begin
		if (reset || state == 0) 
			addr_x <= 0;
		else if (s_valid) begin
			if (((state2_done == 0 && state == 2) || state3_donefinal == 0) && state3_jump != 1)
				addr_x <= addr_x + 1;
			else if (H == 1 && (state == 3 || state == 4)) 
				addr_x <= addr_x;
			else if (state3_jump == 1)
				addr_x <= addr_x + X - H + 1;
			else 
				addr_x <= addr_xjump;
		end
	end

	always @(posedge clk) begin
		if (reset || state == 0)	
			addr_xjump <= 0;
		else if (state3_jump == 1 && state53_done != 1 && addr_h < (H + 1))
			addr_xjump <= addr_xjump + 1;
		else if (state3_jump == 1 && state53_done == 1 && addr_h < (H + 1))
			addr_xjump <= addr_xjump + H;
	end

	always @(posedge clk) begin
		if (reset) 
			addr_y <= 0;
		else if ((state == 5) && (state5_done != 1))
			addr_y <= addr_y + 1;
		else if ((state == 7 && next_state == 7) || state == 6) begin
			if (m_ready)
				addr_y <= addr_y + 1;
		end
	end
	
	always @(posedge clk) begin
		if (reset) 
			clear_acc <= 0;
		else if (state == 5 || state == 2 || state == 9)
			clear_acc <= 1;
		else
			clear_acc <= 0;
	end

	assign wr_en_h = (state == 1 && reset == 0);
	assign wr_en_x = (state == 2 && reset == 0);
	assign wr_en_y = (state == 5 && reset == 0);

endmodule
