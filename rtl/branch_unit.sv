module branch_unit
  import riscv_pkg::*;
(
  input  logic [31:0] pc,
  input  logic [31:0] rs1, rs2,
  input  logic [31:0] imm,
  input  logic [2:0]  funct3,
  input  logic        is_branch, is_jal, is_jalr,
  output logic        taken,
  output logic [31:0] target,
  output logic [31:0] next_pc
);
  logic cond;
  always_comb begin
    unique case (funct3)
      F3_BEQ:  cond = (rs1 == rs2);
      F3_BNE:  cond = (rs1 != rs2);
      F3_BLT:  cond = ($signed(rs1) <  $signed(rs2));
      F3_BGE:  cond = ($signed(rs1) >= $signed(rs2));
      F3_BLTU: cond = (rs1 <  rs2);
      F3_BGEU: cond = (rs1 >= rs2);
      default: cond = 1'b0;
    endcase
  end

  assign taken   = is_jal || is_jalr || (is_branch && cond);

  assign target  = is_jalr ? ((rs1 + imm) & ~32'd1) : (pc + imm);
  assign next_pc = taken ? target : (pc + 32'd4);
endmodule
