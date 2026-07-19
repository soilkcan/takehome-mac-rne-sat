`timescale 1ns/1ps
//
// mac_rne_sat -- implement per doc/spec.md.
// Do not change the module name, port list, or port directions.
// Synthesizable SystemVerilog only (Icarus Verilog, -g2012). No SVA.
//
module mac_rne_sat (
    input  logic               clk,
    input  logic               rst,       // synchronous, active-high
    input  logic               en,        // accumulate a*b this cycle
    input  logic               clr,       // clear accumulator this cycle
    input  logic               rd,        // request readout snapshot this cycle
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [15:0] res,       // rounded + saturated snapshot
    output logic               res_valid, // 1-cycle pulse, one cycle after rd
    output logic               ovf        // sticky saturation flag
);

    // Accumulator: 28-bit signed two's complement.
    logic signed [27:0] acc;

    // Product, sign-extended to accumulator width.
    logic signed [27:0] p;
    logic signed [15:0] mul_result;
    
    assign mul_result = a * b;
    assign p 	      = {{12{mul_result[15]}}, mul_result}; 
    
    // Rounding: q = floor(acc/256), r = acc mod 256 (always between 0 and 256)
    logic signed [27:0] q;
    logic signed [27:0] rounded;
    logic	 [ 7:0] r;
    
    logic signed [15:0] res_sat;
    logic		sat_flag;
    
    always_comb begin
    	q = acc >>> 8; // Arithmetical right shift
    	r = acc[7:0];
    	
    	if (r < 8'd128) begin 
    		rounded = q;
    	end else if (r > 8'd128) begin 
    		rounded = q + 1; 
    	end else begin // round half to even
    		if (q[0] == 1'b0) begin 
    			rounded = q;
    		end else begin
    			rounded = q + 1;
    		end
    	end	
    	
    	// Saturation: rounded value is clamped to the signed 16-bit range
    	if (rounded > 28'sd32767) begin
        	res_sat  = 16'sd32767;
        	sat_flag = 1'b1;
    	end else if (rounded < -28'sd32768) begin
        	res_sat  = -16'sd32768;
        	sat_flag = 1'b1;
    	end else begin
        	res_sat  = rounded[15:0];
        	sat_flag = 1'b0;
    	end
    end
    
    always_ff @(posedge clk) begin
    	if (rst) begin
		acc 	  <= 28'b0;
		res 	  <= 16'b0;
		res_valid <= 1'b0;
		ovf 	  <= 1'b0;
    	end else begin
    		if (rd) begin
    			res 	  <= res_sat;
    			res_valid <= 1'b1;
    			
    			if (sat_flag) begin
    				ovf <= 1'b1;
    			end else if (clr) begin 
    				ovf <= 1'b0;
    			end
    			
    		end else begin
    			res_valid <= 1'b0;
    			
    			if (clr) begin 
    				ovf <= 1'b0;
    			end
    		end
    		
    		case ({clr,en})
    		2'b00: begin // hold state
    			acc <= acc;
    		end
    		2'b01: begin 
    			acc <= acc + p;
    		end
    		2'b10: begin
    			acc <= 28'b0;
    		end
    		2'b11: begin
    			acc <= p;
    		end
    		endcase
    	end
    end

endmodule
