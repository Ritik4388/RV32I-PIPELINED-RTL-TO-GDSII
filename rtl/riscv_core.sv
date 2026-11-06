module riscv_core
  import riscv_pkg::*;
#(
  parameter logic [31:0] BOOT_ADDR  = 32'h8000_0000,
  parameter bit          BP_ENABLE  = 1'b1,
  parameter int          BP_ENTRIES = 64
)(
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  output logic        rvfi_valid,
  output logic [31:0] rvfi_pc, rvfi_insn,
  output logic        rvfi_rd_we,
  output logic [4:0]  rvfi_rd,
  output logic [31:0] rvfi_rd_wdata,
  output logic        rvfi_mem_we,
  output logic [31:0] rvfi_mem_addr, rvfi_mem_wdata,
  output logic [2:0]  rvfi_mem_size_f3,

  output logic [63:0] perf_cycles, perf_instret,
  output logic [63:0] perf_ctrl_instrs, perf_mispredicts, perf_load_use_stalls
);

  // pipeline registers
  if_id_t  if_id;
  id_ex_t  id_ex;
  ex_mem_t ex_mem;
  mem_wb_t mem_wb;

  logic stall_if, stall_id, flush_id, flush_ex, load_use;
  logic ex_mispredict;
  logic [31:0] ex_next_pc;

  logic [31:0] pc_q, pc_d;
  logic        bp_taken;
  logic [31:0] bp_target;

  logic        ex_is_ctrl, ex_taken;
  logic [31:0] ex_target;

  // IF
  branch_predictor #(.ENTRIES(BP_ENTRIES), .ENABLE(BP_ENABLE)) u_bp (
    .clk, .rst_n,
    .if_pc       (pc_q),
    .pred_taken  (bp_taken),
    .pred_target (bp_target),
    .upd_en      (ex_is_ctrl),
    .upd_pc      (id_ex.pc),
    .upd_is_cond (id_ex.ctrl.is_branch),
    .upd_taken   (ex_taken),
    .upd_target  (ex_target)
  );

  always_comb begin
    // a mispredict from EX always wins, it is the oldest instruction
    if (ex_mispredict)  pc_d = ex_next_pc;
    else if (stall_if)  pc_d = pc_q;
    else if (bp_taken)  pc_d = bp_target;
    else                pc_d = pc_q + 32'd4;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc_q <= BOOT_ADDR;
    else        pc_q <= pc_d;
  end

  assign imem_addr = pc_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_id <= '0;
    end else if (flush_id) begin
      if_id.valid <= 1'b0;
    end else if (!stall_id) begin
      if_id.valid       <= 1'b1;
      if_id.pc          <= pc_q;
      if_id.instr       <= imem_rdata;
      if_id.pred_taken  <= bp_taken;
      if_id.pred_target <= bp_target;
    end
  end

  // ID
  ctrl_t       id_ctrl;
  logic [31:0] id_rs1_data, id_rs2_data;
  logic        wb_we;

  decoder u_dec (.instr(if_id.instr), .ctrl(id_ctrl));

  assign wb_we = mem_wb.valid && mem_wb.reg_write;

  regfile u_rf (
    .clk, .rst_n,
    .raddr1 (id_ctrl.rs1), .rdata1 (id_rs1_data),
    .raddr2 (id_ctrl.rs2), .rdata2 (id_rs2_data),
    .we     (wb_we),
    .waddr  (mem_wb.rd),
    .wdata  (mem_wb.wb_data)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex <= '0;
    end else if (flush_ex) begin
      id_ex.valid <= 1'b0;
      id_ex.ctrl  <= '0;

    end else begin
      id_ex.valid       <= if_id.valid;
      id_ex.pc          <= if_id.pc;
      id_ex.instr       <= if_id.instr;
      id_ex.ctrl        <= id_ctrl;
      id_ex.rs1_data    <= id_rs1_data;
      id_ex.rs2_data    <= id_rs2_data;
      id_ex.pred_taken  <= if_id.pred_taken;
      id_ex.pred_target <= if_id.pred_target;
    end
  end

  // EX
  fwd_sel_e    fwd_a, fwd_b;
  logic [31:0] ex_rs1, ex_rs2, alu_a, alu_b, alu_y;
  logic [31:0] exmem_fwd_data;
  logic [31:0] pred_next_pc;

  forwarding_unit u_fwd (
    .ex_rs1          (id_ex.ctrl.rs1),
    .ex_rs2          (id_ex.ctrl.rs2),
    .exmem_valid     (ex_mem.valid),
    .exmem_reg_write (ex_mem.ctrl.reg_write),
    .exmem_rd        (ex_mem.ctrl.rd),
    .memwb_valid     (mem_wb.valid),
    .memwb_reg_write (mem_wb.reg_write),
    .memwb_rd        (mem_wb.rd),
    .fwd_a, .fwd_b
  );

  // jal/jalr write pc+4, not the alu result
  assign exmem_fwd_data = (ex_mem.ctrl.wb_sel == WB_PC4) ? ex_mem.pc + 32'd4
                                                         : ex_mem.alu_result;

  always_comb begin
    unique case (fwd_a)
      FWD_EXMEM: ex_rs1 = exmem_fwd_data;
      FWD_MEMWB: ex_rs1 = mem_wb.wb_data;
      default:   ex_rs1 = id_ex.rs1_data;
    endcase
    unique case (fwd_b)
      FWD_EXMEM: ex_rs2 = exmem_fwd_data;
      FWD_MEMWB: ex_rs2 = mem_wb.wb_data;
      default:   ex_rs2 = id_ex.rs2_data;
    endcase
  end

  always_comb begin
    unique case (id_ex.ctrl.opa_sel)
      OPA_PC:   alu_a = id_ex.pc;
      OPA_ZERO: alu_a = 32'd0;
      default:  alu_a = ex_rs1;
    endcase
    alu_b = (id_ex.ctrl.opb_sel == OPB_IMM) ? id_ex.ctrl.imm : ex_rs2;
  end

  alu u_alu (.op(id_ex.ctrl.alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  branch_unit u_bru (
    .pc        (id_ex.pc),
    .rs1       (ex_rs1),
    .rs2       (ex_rs2),
    .imm       (id_ex.ctrl.imm),
    .funct3    (id_ex.ctrl.funct3),
    .is_branch (id_ex.ctrl.is_branch),
    .is_jal    (id_ex.ctrl.is_jal),
    .is_jalr   (id_ex.ctrl.is_jalr),
    .taken     (ex_taken),
    .target    (ex_target),
    .next_pc   (ex_next_pc)
  );

  assign ex_is_ctrl    = id_ex.valid && (id_ex.ctrl.is_branch || id_ex.ctrl.is_jal ||
                                         id_ex.ctrl.is_jalr);
  assign pred_next_pc  = id_ex.pred_taken ? id_ex.pred_target : id_ex.pc + 32'd4;
  // wrong if the real next pc is not the one we fetched
  assign ex_mispredict = id_ex.valid && (ex_next_pc != pred_next_pc);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem <= '0;
    end else begin
      ex_mem.valid      <= id_ex.valid;
      ex_mem.pc         <= id_ex.pc;
      ex_mem.instr      <= id_ex.instr;
      ex_mem.ctrl       <= id_ex.ctrl;
      ex_mem.alu_result <= alu_y;
      ex_mem.store_data <= ex_rs2;  // forwarded value, not the old register value
    end
  end

  // MEM
  logic [1:0]  byte_off;
  logic [31:0] load_shifted, load_data;

  assign byte_off  = ex_mem.alu_result[1:0];
  assign dmem_addr = ex_mem.alu_result;
  assign dmem_req  = ex_mem.valid && (ex_mem.ctrl.mem_read || ex_mem.ctrl.mem_write);
  assign dmem_we   = ex_mem.valid && ex_mem.ctrl.mem_write;

  always_comb begin
    unique case (ex_mem.ctrl.funct3[1:0])
      2'b00:   begin dmem_be = 4'b0001 << byte_off;           dmem_wdata = {4{ex_mem.store_data[7:0]}};  end
      2'b01:   begin dmem_be = 4'b0011 << {byte_off[1], 1'b0}; dmem_wdata = {2{ex_mem.store_data[15:0]}}; end
      default: begin dmem_be = 4'b1111;                        dmem_wdata = ex_mem.store_data;           end
    endcase
  end

  assign load_shifted = dmem_rdata >> {byte_off, 3'b000};
  always_comb begin
    unique case (ex_mem.ctrl.funct3)
      F3_B:    load_data = {{24{load_shifted[7]}},  load_shifted[7:0]};
      F3_H:    load_data = {{16{load_shifted[15]}}, load_shifted[15:0]};
      F3_BU:   load_data = {24'b0, load_shifted[7:0]};
      F3_HU:   load_data = {16'b0, load_shifted[15:0]};
      default: load_data = dmem_rdata;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_wb <= '0;
    end else begin
      mem_wb.valid     <= ex_mem.valid;
      mem_wb.pc        <= ex_mem.pc;
      mem_wb.instr     <= ex_mem.instr;
      mem_wb.rd        <= ex_mem.ctrl.rd;
      mem_wb.reg_write <= ex_mem.ctrl.reg_write;
      unique case (ex_mem.ctrl.wb_sel)
        WB_MEM:  mem_wb.wb_data <= load_data;
        WB_PC4:  mem_wb.wb_data <= ex_mem.pc + 32'd4;
        default: mem_wb.wb_data <= ex_mem.alu_result;
      endcase
      mem_wb.mem_write <= ex_mem.ctrl.mem_write;
      mem_wb.mem_addr  <= ex_mem.alu_result;
      mem_wb.mem_wdata <= ex_mem.store_data;
      mem_wb.funct3    <= ex_mem.ctrl.funct3;
    end
  end

  // WB, commit log port for the testbench
  assign rvfi_valid       = mem_wb.valid;
  assign rvfi_pc          = mem_wb.pc;
  assign rvfi_insn        = mem_wb.instr;
  assign rvfi_rd_we       = mem_wb.reg_write;
  assign rvfi_rd          = mem_wb.rd;
  assign rvfi_rd_wdata    = mem_wb.wb_data;
  assign rvfi_mem_we      = mem_wb.mem_write;
  assign rvfi_mem_addr    = mem_wb.mem_addr;
  assign rvfi_mem_wdata   = mem_wb.mem_wdata;
  assign rvfi_mem_size_f3 = mem_wb.funct3;

  // hazards
  hazard_unit u_hz (
    .id_valid      (if_id.valid),
    .id_rs1        (id_ctrl.rs1),
    .id_rs2        (id_ctrl.rs2),
    .id_rs1_used   (id_ctrl.rs1_used),
    .id_rs2_used   (id_ctrl.rs2_used),
    .ex_valid      (id_ex.valid),
    .ex_mem_read   (id_ex.ctrl.mem_read),
    .ex_rd         (id_ex.ctrl.rd),
    .ex_mispredict (ex_mispredict),
    .stall_if, .stall_id, .flush_id, .flush_ex, .load_use
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_cycles <= '0; perf_instret <= '0; perf_ctrl_instrs <= '0;
      perf_mispredicts <= '0; perf_load_use_stalls <= '0;
    end else begin
      perf_cycles <= perf_cycles + 1;
      if (mem_wb.valid)  perf_instret         <= perf_instret + 1;
      if (ex_is_ctrl)    perf_ctrl_instrs     <= perf_ctrl_instrs + 1;
      if (ex_mispredict) perf_mispredicts     <= perf_mispredicts + 1;
      if (load_use)      perf_load_use_stalls <= perf_load_use_stalls + 1;
    end
  end

endmodule
