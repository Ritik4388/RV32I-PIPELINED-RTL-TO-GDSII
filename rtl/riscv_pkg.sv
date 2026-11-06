package riscv_pkg;

  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  localparam logic [31:0] NOP = 32'h0000_0013;

  localparam logic [2:0] F3_BEQ  = 3'b000, F3_BNE  = 3'b001,
                         F3_BLT  = 3'b100, F3_BGE  = 3'b101,
                         F3_BLTU = 3'b110, F3_BGEU = 3'b111;

  localparam logic [2:0] F3_B  = 3'b000, F3_H  = 3'b001, F3_W = 3'b010,
                         F3_BU = 3'b100, F3_HU = 3'b101;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { OPA_RS1, OPA_PC, OPA_ZERO } opa_sel_e;
  typedef enum logic       { OPB_RS2, OPB_IMM }          opb_sel_e;
  typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4 }    wb_sel_e;

  typedef enum logic [1:0] { FWD_NONE, FWD_EXMEM, FWD_MEMWB } fwd_sel_e;

  typedef struct packed {
    logic [4:0]  rs1, rs2, rd;
    logic        rs1_used, rs2_used;
    logic [31:0] imm;
    alu_op_e     alu_op;
    opa_sel_e    opa_sel;
    opb_sel_e    opb_sel;
    logic        reg_write;
    wb_sel_e     wb_sel;
    logic        mem_read, mem_write;
    logic [2:0]  funct3;
    logic        is_branch, is_jal, is_jalr;
    logic        illegal;
  } ctrl_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, instr;
    logic        pred_taken;
    logic [31:0] pred_target;
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, instr;
    ctrl_t       ctrl;
    logic [31:0] rs1_data, rs2_data;
    logic        pred_taken;
    logic [31:0] pred_target;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, instr;
    ctrl_t       ctrl;
    logic [31:0] alu_result;
    logic [31:0] store_data;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, instr;
    logic [4:0]  rd;
    logic        reg_write;
    logic [31:0] wb_data;

    // these are only for the commit log
    logic        mem_write;
    logic [31:0] mem_addr, mem_wdata;
    logic [2:0]  funct3;
  } mem_wb_t;

endpackage
