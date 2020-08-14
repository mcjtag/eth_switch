`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Dmitry Matyunin (https://github.com/mcjtag)
// 
// Create Date: 03.08.2020 15:48:00
// Design Name: 
// Module Name: mactable
// Project Name: eth_switch
// Target Devices: 
// Tool Versions: 
// Description: MAC Table
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

module mactable #(
	parameter ADDR_WIDTH = 8,
	parameter PORT_WIDTH = 8,
	parameter RAM_STYLE_DATA = "block",	/* "block" or "distributed" */
	parameter MODE = "static"			/* "static or "dynamic" */
)
(
	input wire aclk,
	input wire aresetn,
	// Table read request
	input wire [95:0]s_axis_table_request_tdata,
	input wire [PORT_WIDTH-1:0]s_axis_table_request_tuser,
	input wire s_axis_table_request_tvalid,
	output wire s_axis_table_request_tready,
	// Table read response
	output wire [3:0]m_axis_table_response_tdata,
	output wire [PORT_WIDTH*2-1:0]m_axis_table_response_tuser,
	output wire m_axis_table_response_tvalid,
	/* Table Config */
	input wire [ADDR_WIDTH+PORT_WIDTH+47:0]s_axis_table_config_tdata,
	input wire s_axis_table_config_tuser,
	input wire s_axis_table_config_tvalid
);

localparam [2:0]
	STATE_REQUEST = 0,
	STATE_DST_RESOLVE_REQ = 1,
	STATE_DST_RESOLVE_RES = 2,
	STATE_DST_RESPONSE = 3,
	STATE_SRC_RESOLVE_REQ = 4,
	STATE_SRC_RESOLVE_RES = 5,
	STATE_SRC_UPDATE = 6;

localparam [3:0]
	STATUS_OK = 0,		/* Okay */
	STATUS_NIT = 1,		/* Not In Table */
	STATUS_ERR = 2;		/* Error */

localparam CONFIG_WIDTH = ADDR_WIDTH+PORT_WIDTH+48;
localparam RESPONSE_WIDTH = ADDR_WIDTH+PORT_WIDTH;
localparam REQUEST_WIDTH = 48;

reg [2:0]state;
reg [3:0]status;

reg req_ready;
reg res_valid;

reg [47:0]mac_src;
reg [47:0]mac_dst;
reg [PORT_WIDTH-1:0]port_src;
reg [PORT_WIDTH-1:0]port_dst;
reg [ADDR_WIDTH-1:0]port_addr;
reg [ADDR_WIDTH-1:0]curr_addr;

reg [CONFIG_WIDTH-1:0]config_data;
reg config_user;
reg config_valid;
reg [REQUEST_WIDTH-1:0]request_data;
reg request_valid;
wire request_ready;
wire [RESPONSE_WIDTH-1:0]response_data;
wire response_user;
wire response_valid;
wire [CONFIG_WIDTH-1:0]axis_config_data;
wire axis_config_user;
wire axis_config_valid;

assign s_axis_table_request_tready = req_ready;
assign m_axis_table_response_tdata = status;
assign m_axis_table_response_tuser = {port_src,port_dst};
assign m_axis_table_response_tvalid = res_valid;

generate if (MODE == "dynamic") begin
	assign axis_config_data = config_data;
	assign axis_config_user = config_user;
	assign axis_config_valid= config_valid;
end else begin
	assign axis_config_data = s_axis_table_config_tdata;
	assign axis_config_user = s_axis_table_config_tuser;
	assign axis_config_valid= s_axis_table_config_tvalid;
end endgenerate

always @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		mac_src <= 0;
		mac_dst <= 0;
		port_src <= 0;
		port_dst <= 0;
		port_addr <= 0;
		status <= 0;
		request_valid <= 1'b0;
		curr_addr <= 0;
		config_data <= 0;
		config_user <= 1'b0;
		config_valid <= 1'b0;
		state <= STATE_REQUEST;
	end else begin
		case (state)
		STATE_REQUEST: begin
			if ((s_axis_table_request_tvalid == 1'b1) && (s_axis_table_request_tready == 1'b1)) begin
				{mac_src,mac_dst} <= s_axis_table_request_tdata;
				port_src <= s_axis_table_request_tuser;
				state <= STATE_DST_RESOLVE_REQ;
			end
		end
		STATE_DST_RESOLVE_REQ: begin
			if (request_valid == 1'b0) begin
				request_valid <= 1'b1;
				request_data <= mac_dst;
			end else begin
				if (request_ready == 1'b1) begin
					request_valid <= 1'b0;
					state <= STATE_DST_RESOLVE_RES;
				end
			end
		end
		STATE_DST_RESOLVE_RES: begin
			if (response_valid == 1'b1) begin
				{port_dst, port_addr} <= response_data;
				if (response_user == 1'b1) begin
					status <= STATUS_NIT;
				end else begin
					status <= STATUS_OK;
				end
				state <= STATE_DST_RESPONSE;
			end
		end
		STATE_DST_RESPONSE: begin
			if (MODE == "dynamic") begin
				state <= STATE_SRC_RESOLVE_REQ;
			end else begin
				state <= STATE_REQUEST;
			end
		end
		STATE_SRC_RESOLVE_REQ: begin
			if (request_valid == 1'b0) begin
				request_valid <= 1'b1;
				request_data <= mac_src;
			end else begin
				if (request_ready == 1'b1) begin
					request_valid <= 1'b0;
					state <= STATE_SRC_RESOLVE_RES;
				end
			end
		end
		STATE_SRC_RESOLVE_RES: begin
			if (response_valid == 1'b1) begin
				if (response_user == 1'b1) begin
					state <= STATE_SRC_UPDATE;
				end else begin
					port_addr <= response_data[ADDR_WIDTH-1:0];
					if (port_src == response_data[ADDR_WIDTH+PORT_WIDTH-1:ADDR_WIDTH]) begin
						state <= STATE_REQUEST;
					end else begin
						state <= STATE_SRC_UPDATE;	
					end
				end
			end
		end
		STATE_SRC_UPDATE: begin
			if (config_valid == 1'b0) begin
				config_valid <= 1'b1;
				config_data <= {mac_src,port_src,curr_addr};
				config_user <= 1'b0;
				curr_addr <= curr_addr + 1;
			end else begin
				config_valid <= 1'b0;
				state <= STATE_REQUEST;
			end
		end
		default: state <= STATE_REQUEST;
		endcase
	end
end

always @(*) begin
	case (state)
	STATE_REQUEST: begin
		req_ready <= 1'b1;
		res_valid <= 1'b0;
	end
	STATE_DST_RESPONSE: begin
		req_ready <= 1'b0;
		res_valid <= 1'b1;
	end
	default: begin
		req_ready <= 1'b0;
		res_valid <= 1'b0;
	end
	endcase
end

mactable_cam #(
	.ADDR_WIDTH(ADDR_WIDTH),
	.KEY_WIDTH(48),
	.DATA_WIDTH(PORT_WIDTH),
	.RAM_STYLE_DATA(RAM_STYLE_DATA),
	.CONFIG_WIDTH(CONFIG_WIDTH),
	.REQUEST_WIDTH(REQUEST_WIDTH),
	.RESPONSE_WIDTH(RESPONSE_WIDTH)
) mactable_cam_inst (
	.aclk(aclk),
	.aresetn(aresetn),
	.s_axis_config_tdata(axis_config_data),
	.s_axis_config_tuser(axis_config_user),
	.s_axis_config_tvalid(axis_config_valid),
	.s_axis_request_tdata(request_data),
	.s_axis_request_tvalid(request_valid),
	.s_axis_request_tready(request_ready),
	.m_axis_response_tdata(response_data),
	.m_axis_response_tuser(response_user),
	.m_axis_response_tvalid(response_valid)
);

endmodule