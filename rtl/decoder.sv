module decoder
  import riscv_pkg::*;
(
  input  logic [31:0] instr,
  output ctrl_t       ctrl
);
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{21{instr[31]}}, instr[30:20]};
  assign imm_s = {{21{instr[31]}}, instr[30:25], instr[11:7]};
  assign imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};
  assign imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

  function automatic alu_op_e alu_from_f3(input logic [2:0] f3, input logic f7b5,
                                          input logic is_reg);
    case (f3)
      3'b000:  return (is_reg && f7b5) ? ALU_SUB : ALU_ADD;
      3'b001:  return ALU_SLL;
      3'b010:  return ALU_SLT;
      3'b011:  return ALU_SLTU;
      3'b100:  return ALU_XOR;
      3'b101:  return f7b5 ? ALU_SRA : ALU_SRL;
      3'b110:  return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  always_comb begin
    ctrl           = '0;
    ctrl.rs1       = instr[19:15];
    ctrl.rs2       = instr[24:20];
    ctrl.rd        = instr[11:7];
    ctrl.funct3    = funct3;
    ctrl.alu_op    = ALU_ADD;
    ctrl.opa_sel   = OPA_RS1;
    ctrl.opb_sel   = OPB_IMM;
    ctrl.wb_sel    = WB_ALU;

    unique case (opcode)
      OP_LUI: begin
        ctrl.imm = imm_u; ctrl.opa_sel = OPA_ZERO; ctrl.reg_write = 1'b1;
      end
      OP_AUIPC: begin
        ctrl.imm = imm_u; ctrl.opa_sel = OPA_PC;   ctrl.reg_write = 1'b1;
      end
      OP_JAL: begin
        ctrl.imm = imm_j; ctrl.is_jal = 1'b1;
        ctrl.reg_write = 1'b1; ctrl.wb_sel = WB_PC4;
      end
      OP_JALR: begin
        ctrl.imm = imm_i; ctrl.is_jalr = 1'b1; ctrl.rs1_used = 1'b1;
        ctrl.reg_write = 1'b1; ctrl.wb_sel = WB_PC4;
        ctrl.illegal = (funct3 != 3'b000);
      end
      OP_BRANCH: begin
        ctrl.imm = imm_b; ctrl.is_branch = 1'b1;
        ctrl.rs1_used = 1'b1; ctrl.rs2_used = 1'b1;
        ctrl.illegal = (funct3 == 3'b010) || (funct3 == 3'b011);
      end
      OP_LOAD: begin
        ctrl.imm = imm_i; ctrl.rs1_used = 1'b1; ctrl.mem_read = 1'b1;
        ctrl.reg_write = 1'b1; ctrl.wb_sel = WB_MEM;
        ctrl.illegal = !(funct3 inside {F3_B, F3_H, F3_W, F3_BU, F3_HU});
      end
      OP_STORE: begin
        ctrl.imm = imm_s; ctrl.rs1_used = 1'b1; ctrl.rs2_used = 1'b1;
        ctrl.mem_write = 1'b1;
        ctrl.illegal = !(funct3 inside {F3_B, F3_H, F3_W});
      end
      OP_IMM: begin
        ctrl.imm = imm_i; ctrl.rs1_used = 1'b1; ctrl.reg_write = 1'b1;
        ctrl.alu_op = alu_from_f3(funct3, instr[30], 1'b0);
      end
      OP_REG: begin
        ctrl.rs1_used = 1'b1; ctrl.rs2_used = 1'b1; ctrl.reg_write = 1'b1;
        ctrl.opb_sel = OPB_RS2;
        ctrl.alu_op  = alu_from_f3(funct3, funct7[5], 1'b1);
        ctrl.illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
      end
      OP_FENCE: ;
      OP_SYSTEM: begin
        // only "csrr rd, mhartid" is supported, riscv-dv startup needs it
        if ((funct3 == 3'b010 || funct3 == 3'b011) && instr[19:15] == 5'd0 &&
            instr[31:20] == 12'hF14) begin
          ctrl.opa_sel = OPA_ZERO; ctrl.imm = 32'd0; ctrl.reg_write = 1'b1;
        end else begin
          ctrl.illegal = 1'b1;
        end
      end
      default: ctrl.illegal = 1'b1;
    endcase

    // x0 is never written, and unused fields must not look like real sources
    if (ctrl.rd == 5'd0) ctrl.reg_write = 1'b0;
    if (!ctrl.rs1_used)  ctrl.rs1 = 5'd0;
    if (!ctrl.rs2_used)  ctrl.rs2 = 5'd0;
  end
endmodule
