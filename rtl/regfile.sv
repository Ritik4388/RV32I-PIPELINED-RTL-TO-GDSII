module regfile (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [4:0]  raddr1, raddr2,
  output logic [31:0] rdata1, rdata2,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata
);
  logic [31:0] regs [32];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) regs[i] <= '0;
    end else if (we && waddr != 5'd0) begin
      regs[waddr] <= wdata;
    end
  end

  // reading a register while it is being written gives the new value
  always_comb begin
    rdata1 = (raddr1 == 5'd0) ? '0 :
             (we && waddr == raddr1) ? wdata : regs[raddr1];
    rdata2 = (raddr2 == 5'd0) ? '0 :
             (we && waddr == raddr2) ? wdata : regs[raddr2];
  end
endmodule
