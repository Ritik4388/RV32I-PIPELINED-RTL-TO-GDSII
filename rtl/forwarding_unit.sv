module forwarding_unit
  import riscv_pkg::*;
(
  input  logic [4:0] ex_rs1, ex_rs2,
  input  logic       exmem_valid, exmem_reg_write,
  input  logic [4:0] exmem_rd,
  input  logic       memwb_valid, memwb_reg_write,
  input  logic [4:0] memwb_rd,
  output fwd_sel_e   fwd_a, fwd_b
);
  logic exmem_wr, memwb_wr;
  assign exmem_wr = exmem_valid && exmem_reg_write && (exmem_rd != 5'd0);
  assign memwb_wr = memwb_valid && memwb_reg_write && (memwb_rd != 5'd0);

  // EX/MEM is checked last so the newer result wins
  always_comb begin
    fwd_a = FWD_NONE;
    if (memwb_wr && memwb_rd == ex_rs1) fwd_a = FWD_MEMWB;
    if (exmem_wr && exmem_rd == ex_rs1) fwd_a = FWD_EXMEM;

    fwd_b = FWD_NONE;
    if (memwb_wr && memwb_rd == ex_rs2) fwd_b = FWD_MEMWB;
    if (exmem_wr && exmem_rd == ex_rs2) fwd_b = FWD_EXMEM;
  end
endmodule
