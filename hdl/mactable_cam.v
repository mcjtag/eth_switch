`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Dmitry Matyunin (https://github.com/mcjtag)
// 
// Create Date: 02.08.2020 17:12:29
// Design Name: 
// Module Name: mactable_cam
// Project Name: eth_switch
// Target Devices: 
// Tool Versions: 
// Description: CAM MAC-address table
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// License: MIT
//  Copyright (c) 2020 Dmitry Matyunin
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
// 
//////////////////////////////////////////////////////////////////////////////////

module mactable_cam #(
	parameter ADDR_WIDTH = 4,
	parameter KEY_WIDTH = 4,
	parameter DATA_WIDTH = 4,
	parameter RAM_STYLE_DATA = "block",
	parameter CONFIG_WIDTH = ADDR_WIDTH+DATA_WIDTH+KEY_WIDTH,
	parameter REQUEST_WIDTH = KEY_WIDTH,
	parameter RESPONSE_WIDTH = ADDR_WIDTH+DATA_WIDTH
)
(
	input wire aclk,
	input wire aresetn,
	input wire [CONFIG_WIDTH-1:0]s_axis_config_tdata,
	input wire s_axis_config_tuser,
	input wire s_axis_config_tvalid,
	/* Request */
	input wire [REQUEST_WIDTH-1:0]s_axis_request_tdata,
	input wire s_axis_request_tvalid,
	output wire s_axis_request_tready,
	/* Response */
	output wire [RESPONSE_WIDTH-1:0]m_axis_response_tdata,
	output wire m_axis_response_tuser,
	output wire m_axis_response_tvalid
);

localparam ADDR_OFFSET = ADDR_WIDTH;
localparam DATA_OFFSET = ADDR_OFFSET+DATA_WIDTH;
localparam KEY_OFFSET = DATA_OFFSET+KEY_WIDTH;

wire [ADDR_WIDTH-1:0]set_addr; 
wire [DATA_WIDTH-1:0]set_data;
wire [KEY_WIDTH-1:0]set_key;
wire set_clr;
wire set_valid;
wire [KEY_WIDTH-1:0]req_key;
wire req_valid;
wire req_ready;
reg [ADDR_WIDTH-1:0]res_addr;
wire [DATA_WIDTH-1:0]res_data;
reg res_valid;
reg res_null;

reg line_valid;
wire [2**ADDR_WIDTH-1:0]line_match;
wire [ADDR_WIDTH-1:0]enc_addr;
wire enc_valid;
wire enc_null;

assign set_addr = s_axis_config_tdata[ADDR_OFFSET-1-:ADDR_WIDTH]; 
assign set_data = s_axis_config_tdata[DATA_OFFSET-1-:DATA_WIDTH];
assign set_key = s_axis_config_tdata[KEY_OFFSET-1-:KEY_WIDTH];
assign set_clr = s_axis_config_tuser;
assign set_valid = s_axis_config_tvalid;

assign req_key = s_axis_request_tdata;
assign req_valid = s_axis_request_tvalid;
assign s_axis_request_tready = req_ready;

assign m_axis_response_tdata = {res_data,res_addr};
assign m_axis_response_tuser = res_null;
assign m_axis_response_tvalid = res_valid;

assign req_ready = (aresetn == 1'b0) ? 1'b0 : ~(line_valid | enc_valid | res_valid);

always @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		line_valid <= 1'b0;
		res_addr <= 0;
		res_valid <= 1'b0;
		res_null <= 1'b0;
	end else begin
		line_valid <= req_valid;
		res_addr <= enc_addr;
		res_valid <= enc_valid;
		res_null <= enc_null;
	end
end

mactable_cam_line_array #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.KEY_WIDTH(KEY_WIDTH)
) mactable_cam_line_array_inst (
	.clk(aclk),
	.rst(~aresetn),
	.set_addr(set_addr),
	.set_key(set_key),
	.set_clr(set_clr),
	.set_valid(set_valid),
	.req_key(req_key),
	.req_valid(req_valid & req_ready),
	.line_match(line_match)
);

mactable_cam_line_encoder #(
	.ADDR_WIDTH(ADDR_WIDTH)
) mactable_cam_line_encoder_inst (
	.clk(aclk),
	.rst(~aresetn),
	.line_match(line_match),
	.line_valid(line_valid),
	.addr(enc_addr),
	.addr_valid(enc_valid),
	.addr_null(enc_null)
);

mactable_cam_sdpram #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.DATA_WIDTH(DATA_WIDTH),
	.RAM_STYLE(RAM_STYLE_DATA)
) mactable_cam_sdpram_inst (
	.clk(aclk),
	.rst(~aresetn),
	.dina(set_data),
	.addra(set_addr),
	.addrb(enc_addr),
	.wea(set_valid),
	.doutb(res_data)
);

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Module Name: mactable_cam_line_array
// Project Name: eth_switch
// Description: CAM Index Memory Array
//////////////////////////////////////////////////////////////////////////////////
module mactable_cam_line_array #(
	parameter ADDR_WIDTH = 8,
	parameter KEY_WIDTH = 8
)
(
	input wire clk,
	input wire rst,
	input wire [ADDR_WIDTH-1:0]set_addr,
	input wire [KEY_WIDTH-1:0]set_key,
	input wire set_clr,
	input wire set_valid,
	input wire [KEY_WIDTH-1:0]req_key,
	input wire req_valid,
	output wire [2**ADDR_WIDTH-1:0]line_match
);

localparam MEM_WIDTH = KEY_WIDTH;

reg [MEM_WIDTH-1:0]mem[2**ADDR_WIDTH-1:0];
reg [2**ADDR_WIDTH-1:0]active;
reg [2**ADDR_WIDTH-1:0]match;
wire [KEY_WIDTH-1:0]key[2**ADDR_WIDTH-1:0];

integer i;
genvar g;

generate for (g = 0; g < 2**ADDR_WIDTH; g = g + 1) begin
	wire [MEM_WIDTH-1:0]mem_tmp;
	assign mem_tmp = mem[g];
	assign key[g] = mem_tmp;
end endgenerate

assign line_match = match;

/* Initial */
initial begin
	for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
		mem[i] = 0;
	end
end

/* Set */
always @(posedge clk) begin
	if (rst == 1'b1) begin
		active = {KEY_WIDTH{1'b0}};
	end else begin
		if (set_valid == 1'b1) begin
			for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
				if (set_addr == i) begin
					mem[i] <= set_key;
					active[i] <= ~set_clr;
				end
			end
		end
	end
end

/* Request */
always @(posedge clk) begin
	if (rst == 1'b1) begin
		match <= {2**ADDR_WIDTH{1'b0}};
	end else begin
		if (req_valid == 1'b1) begin
			for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
				match[i] <= ((key[i] ^ req_key) == 0) & active[i];
			end
		end
	end
end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Module Name: mactable_cam_line_encoder
// Project Name: eth_switch
// Description: CAM Matched Lines Encoder
//////////////////////////////////////////////////////////////////////////////////
module mactable_cam_line_encoder #(
	parameter ADDR_WIDTH = 8
)
(
	input wire clk,
	input wire rst,
	input wire [2**ADDR_WIDTH-1:0]line_match,
	input wire line_valid,
	output wire [ADDR_WIDTH-1:0]addr,
	output wire addr_valid,
	output wire addr_null
);

reg encode;
reg [2**ADDR_WIDTH-1:0]line;
reg [ADDR_WIDTH-1:0]addr_out;
reg valid_out;
reg null_out;
integer i;

assign addr = addr_out;
assign addr_valid = valid_out;
assign addr_null = null_out;

always @(posedge clk) begin
	if (rst == 1'b1) begin
		encode <= 1'b0;
	end else begin
		if (encode == 1'b0) begin
			if (line_valid) begin
				line <= line_match;
				encode <= 1'b1;
			end
		end else begin
			if (line == 0) begin
				encode <= 1'b0;
			end else begin
				if ((line & ~(2**addr_out))) begin
					line[addr_out] <= 1'b0;
				end else begin
					encode <= 1'b0;
				end
			end
		end
	end
end

always @(*) begin
	addr_out = 0;
	valid_out = 1'b0;
	null_out = 1'b0;
	
	if (encode == 1'b1) begin
		if (line == 0) begin
			valid_out = 1'b1;
			null_out = 1'b1;
		end else begin
			for (i = 2**ADDR_WIDTH - 1; i >= 0; i = i - 1) begin
				if (line[i] == 1'b1) begin
					addr_out = i;
					valid_out = 1'b1;
				end
			end
		end
	end
end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Module Name: mactable_cam_sdpram
// Project Name: eth_switch
// Description: CAM Data Memory
//////////////////////////////////////////////////////////////////////////////////
module mactable_cam_sdpram #(
	parameter ADDR_WIDTH = 8,
	parameter DATA_WIDTH = 8,
	parameter RAM_STYLE = "block"
)
(
	input wire clk,
	input wire rst,
	input wire [DATA_WIDTH-1:0]dina,
	input wire [ADDR_WIDTH-1:0]addra,
	input wire [ADDR_WIDTH-1:0]addrb,
	input wire wea,
	output wire [DATA_WIDTH-1:0]doutb
);

(* ram_style = RAM_STYLE *)
reg [DATA_WIDTH-1:0]ram[2**ADDR_WIDTH-1:0];
reg [ADDR_WIDTH-1:0]readb;
integer i;

assign doutb = readb;

initial begin
	for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
		ram[i] = 0;
	end
end

always @(posedge clk) begin
	if (wea) begin
		ram[addra] <= dina;
	end
	readb <= ram[addrb];
end

endmodule