module hazard_unit (

  input  logic       id_valid,
  input  logic [4:0] id_rs1, id_rs2,
  input  logic       id_rs1_used, id_rs2_used,

  input  logic       ex_valid, ex_mem_read,
  input  logic [4:0] ex_rd,
  input  logic       ex_mispredict,

  output logic       stall_if,
  output logic       stall_id,
  output logic       flush_id,
  output logic       flush_ex,
  output logic       load_use
);
  assign load_use = id_valid && ex_valid && ex_mem_read && (ex_rd != 5'd0) &&
                    ((id_rs1_used && id_rs1 == ex_rd) ||
                     (id_rs2_used && id_rs2 == ex_rd));

  assign stall_if = load_use;
  assign stall_id = load_use;
  assign flush_id = ex_mispredict;
  assign flush_ex = ex_mispredict || load_use;
endmodule
