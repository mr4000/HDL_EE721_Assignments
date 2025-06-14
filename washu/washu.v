module washu (
    input wire clk,
    input wire reset,
    input wire pause,
    output reg en,
    output reg rw,
    output reg [15:0] aBus,
    inout wire [15:0] dBus,
    input wire [1:0] regSelect,
    output reg [15:0] dispReq
);

   // Enum equivalent in Verilog using parameters
    parameter RESET     = 5'b00000;
    parameter PAUSE     = 5'b00001;
    parameter FETCH     = 5'b00010;
    parameter DECODE    = 5'b00011;
    parameter HALT      = 5'b00100;
    parameter NEGATE    = 5'b00101;
    parameter BRANCH    = 5'b00110;
    parameter BRZERO    = 5'b00111;
    parameter BRPOS     = 5'b01000;
    parameter BRNEG     = 5'b01001;
    parameter BRIND     = 5'b01010;
    parameter CONST_LOAD = 5'b01011;
    parameter DIR_LOAD  = 5'b01100;
    parameter IND_LOAD  = 5'b01101;
    parameter DIR_STORE = 5'b01110;
    parameter IND_STORE = 5'b01111;
    parameter ADD       = 5'b10000;
    parameter ANDD      = 5'b10001;

    reg [4:0] state;
    // Internal registers
    reg [15:0] pc, ireg, iar, acc, alu;
    reg [15:0] this_, opAdr, target;
    reg [3:0] tick;
		 
	 task wrapup;
		begin
			 if (pause) begin
				  state <= PAUSE;
			 end else begin
				  state <= FETCH;
				  tick  <= 4'h0;
			 end
		end
	 endtask

    // FSM logic
    always@(posedge clk or posedge reset) begin
        if (reset) begin
            state <= RESET;
            tick <= 0;
            pc <= 0;
       
			end else begin
				 tick <= tick + 1;
				 case (state)
					  RESET: begin
							tick <= 0;
							state <= FETCH;
					  end
					  
					  PAUSE: begin
							if (pause == 0) begin 
								tick <= 0;
								state <= FETCH;
							end
					  end

					  FETCH: begin
							case (tick)
								 2'd1: begin
									  ireg <= dBus;
								 end
								 2'd2: begin
									  this_ <= pc;
									  pc <= pc + 1;
									  state <= DECODE;
									  tick <= 0;
								 end
							endcase
					  end

					  DECODE: begin
							tick <= 0;
							// Increment PC in DECODE state

							casex (ireg)
								 16'h0000: state <= HALT;
								 16'h0001: state <= NEGATE;
								 16'b00000001????????: state <= BRANCH;   // 0x01xx
								 16'b00000010????????: state <= BRZERO;   // 0x02xx
								 16'b00000011????????: state <= BRPOS;    // 0x03xx
								 16'b00000100????????: state <= BRNEG;    // 0x04xx
								 16'b00000101????????: state <= BRIND;    // 0x05xx
								 16'b0001????????????: state <= CONST_LOAD; // 0x1xxx
								 16'b0010????????????: state <= DIR_LOAD;   // 0x2xxx
								 16'b0011????????????: state <= IND_LOAD;   // 0x3xxx
								 16'b0101????????????: state <= DIR_STORE;  // 0x5xxx
								 16'b0110????????????: state <= IND_STORE;  // 0x6xxx
								 16'b1000????????????: state <= ADD;        // 0x8xxx
								 16'b1100????????????: state <= ANDD;       // 0xCxxx
								 default: state <= HALT;
							endcase
					  end

					  // States for each instruction
					  HALT: begin
					  end

					  NEGATE: begin
							acc <= -acc;
							wrapup();
					  end

					  // Branching instructions
					  BRANCH: begin
							pc <= target;
							wrapup();
					  end

					  BRZERO: begin
							if (acc == 0) begin
								 pc <= target; // Branch if ACC is zero
							end
							wrapup();
					  end

					  BRPOS: begin
							if ($signed(acc) > 0) begin
								 pc <= target; // Branch if ACC is positive
							end
							wrapup();
					  end

					  BRNEG: begin
							if ($signed(acc) < 0) begin
								 pc <= target; // Branch if ACC is negative
							end
							wrapup();
					  end

					  BRIND: begin
							if (tick == 1) begin
								 pc <= dBus; // Indirect branch
								 wrapup();
							end
					  end

					  CONST_LOAD: begin
							acc <= { {4{ireg[11]}}, ireg[11:0] };
							wrapup();
					  end

					  DIR_LOAD: begin
							if (tick == 1) begin
								acc <= dBus;  // Direct load from memory
								wrapup();
							end
					  end

					  IND_LOAD: begin
							if (tick == 1) begin
								iar <= dBus;  // Direct load from memory
							end
							if (tick == 3) begin
								acc <= dBus;  // Direct load from memory
								wrapup();
							end
					  end

					  DIR_STORE: begin
							wrapup();
					  end

					  IND_STORE: begin
							if (tick == 1) begin
								iar <= dBus;  // Direct load from memory
							end
							if (tick == 3) begin
								wrapup();
							end
					  end

					  ADD: begin
							if (tick == 1) begin
								acc <= acc + dBus;
								wrapup();
							end
					  end

					  ANDD: begin
							if (tick == 1) begin
								acc <= acc & dBus;
								wrapup();
							end
					  end

					  default: state <= FETCH;
				 endcase
        end
    end
	 
	 assign dBus = (en && !rw) ? acc : 16'bz;  // Drive dBus if enabled and write signal is low, else high impedance

	 always @* begin
		 opAdr = {this_[15:12],ireg[11:0]};
	    target = this_ + {{8{ireg[7]}},ireg[7:0]};
		 // Default values for memory control signals
		 en   = 1'b0;
		 rw   = 1'b1;
		 aBus = 16'bZ;

		 case (state)
			  FETCH: begin
					if (tick == 4'h0) begin
						 en   = 1'b1;
						 aBus = pc;
					end
			  end

			  DIR_LOAD, ADD, ANDD: begin
					if (tick == 4'h0) begin
						 en   = 1'b1;
						 aBus = opAdr;
					end
			  end

			  IND_LOAD: begin
					if (tick == 4'h0) begin
						 en   = 1'b1;
						 aBus = opAdr;
					end else if (tick == 4'h2) begin
						 en   = 1'b1;
						 aBus = iar;
					end
			  end
			  
			  DIR_STORE: begin
					if (tick == 4'h0) begin
						 rw   = 1'b0;
						 en   = 1'b1;
						 aBus = opAdr;
					end
			  end

			  IND_STORE: begin
					if (tick == 4'h0) begin
						 en   = 1'b1;
						 aBus = opAdr;
					end else if (tick == 4'h2) begin
						 rw   = 1'b0;
						 en   = 1'b1;
						 aBus = iar;
					end
			  end

			  BRIND: begin
					if (tick == 4'h0) begin
						 en   = 1'b1;
						 aBus = opAdr;
					end
			  end
			  default: begin
					// Defaults already assigned above
			  end
		 endcase
	 end


    // Register selection output
    always@(*) begin
        case (regSelect)
            2'b00: dispReq = ireg;
            2'b01: dispReq = pc;
            2'b10: dispReq = acc;
            2'b11: dispReq = alu;
        endcase
    end
endmodule
