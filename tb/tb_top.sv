`timescale 1ns/1ps
module tb_top;
  import riscv_pkg::*;

  localparam logic [31:0] MEM_BASE  = 32'h8000_0000;
  localparam int          MEM_WORDS = 1 << 20;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [31:0] mem [MEM_WORDS];

  function automatic logic in_range(input logic [31:0] a);
    return (a >= MEM_BASE) && (a < MEM_BASE + MEM_WORDS*4);
  endfunction
  function automatic int widx(input logic [31:0] a);
    return int'((a - MEM_BASE) >> 2);
  endfunction

  logic [31:0] imem_addr, imem_rdata;
  logic        dmem_req, dmem_we;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0]  dmem_be;

  // wrong-path fetches can run past memory, feed them nops
  assign imem_rdata = in_range(imem_addr) ? mem[widx(imem_addr)] : NOP;
  assign dmem_rdata = in_range(dmem_addr) ? mem[widx(dmem_addr)] : 32'h0;

  // always, not always_ff: $readmemh also writes mem
  always @(posedge clk) begin
    if (dmem_we && in_range(dmem_addr)) begin
      for (int b = 0; b < 4; b++)
        if (dmem_be[b]) mem[widx(dmem_addr)][8*b +: 8] <= dmem_wdata[8*b +: 8];
    end
  end

  logic        rvfi_valid, rvfi_rd_we, rvfi_mem_we;
  logic [31:0] rvfi_pc, rvfi_insn, rvfi_rd_wdata, rvfi_mem_addr, rvfi_mem_wdata;
  logic [4:0]  rvfi_rd;
  logic [2:0]  rvfi_mem_size_f3;
  logic [63:0] perf_cycles, perf_instret, perf_ctrl, perf_mispred, perf_lu;

  // a gate netlist has no parameters, so it boots from the address it was synthesized with
`ifdef GATE_SIM
  riscv_core dut (
`else
  riscv_core #(.BOOT_ADDR(MEM_BASE)) dut (
`endif
    .clk, .rst_n,
    .imem_addr, .imem_rdata,
    .dmem_req, .dmem_we, .dmem_addr, .dmem_be, .dmem_wdata, .dmem_rdata,
    .rvfi_valid, .rvfi_pc, .rvfi_insn, .rvfi_rd_we, .rvfi_rd, .rvfi_rd_wdata,
    .rvfi_mem_we, .rvfi_mem_addr, .rvfi_mem_wdata, .rvfi_mem_size_f3,
    .perf_cycles, .perf_instret, .perf_ctrl_instrs(perf_ctrl),
    .perf_mispredicts(perf_mispred), .perf_load_use_stalls(perf_lu)
  );

  string       hexfile, tracefile;
  logic [31:0] tohost;
  longint      max_cycles;
  int          fd;

  initial begin
    for (int i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
    if (!$value$plusargs("hex=%s", hexfile)) $fatal(1, "need +hex=<file>");
    if (!$value$plusargs("tohost=%h", tohost)) tohost = 32'hFFFF_FFFF;
    if (!$value$plusargs("trace=%s", tracefile)) tracefile = "rtl_trace.log";
    if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 1_000_000;
    $readmemh(hexfile, mem);
    fd = $fopen(tracefile, "w");
    if ($test$plusargs("vcd")) begin
      $dumpfile("wave.vcd");
      $dumpvars(0, tb_top);
    end
`ifdef XCELIUM
    if ($test$plusargs("shm")) begin
      $shm_open("wave.shm");
      $shm_probe("AS");
    end
`endif
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

  function automatic string store_str(input logic [2:0] f3, input logic [31:0] d);
    case (f3[1:0])
      2'b00:   return $sformatf("0x%02x", d[7:0]);
      2'b01:   return $sformatf("0x%04x", d[15:0]);
      default: return $sformatf("0x%08x", d);
    endcase
  endfunction

`ifndef GATE_SIM
  always @(posedge clk) begin
    // the core cannot trap yet, so just report misaligned accesses
    if (rst_n && dmem_req &&
        ((dut.ex_mem.ctrl.funct3[1:0] == 2'b10 && dmem_addr[1:0] != 2'b00) ||
         (dut.ex_mem.ctrl.funct3[1:0] == 2'b01 && dmem_addr[0])))
      $display("[TB] MISALIGNED %s at pc=0x%08x addr=0x%08x (not supported: no trap logic yet)",
               dmem_we ? "store" : "load", dut.ex_mem.pc, dmem_addr);
  end
`endif

  always @(posedge clk) begin
    if (rst_n && rvfi_valid) begin
      string line;  // one line per retired instruction, same format as spike
      line = $sformatf("core   0: 3 0x%08x (0x%08x)", rvfi_pc, rvfi_insn);
      if (rvfi_rd_we)
        line = {line, $sformatf(" x%-2d 0x%08x", rvfi_rd, rvfi_rd_wdata)};
      if (rvfi_mem_we)
        line = {line, $sformatf(" mem 0x%08x %s", rvfi_mem_addr,
                                store_str(rvfi_mem_size_f3, rvfi_mem_wdata))};
      $fdisplay(fd, "%s", line);

      if (rvfi_mem_we && rvfi_mem_addr == tohost) begin
        $display("[TB] tohost written (0x%08x) - test finished", rvfi_mem_wdata);
        report();
        $fclose(fd);
        $finish;
      end
    end
    if (perf_cycles >= 64'(max_cycles)) begin
      $display("[TB] TIMEOUT after %0d cycles (pc=0x%08x)", perf_cycles, imem_addr);
      report();
      $fclose(fd);
      $fatal(1, "timeout");
    end
  end

  task automatic report();
    real cpi;
    cpi = (perf_instret == 0) ? 0.0 : real'(perf_cycles) / real'(perf_instret);
    $display("[TB] cycles=%0d instret=%0d CPI=%.3f", perf_cycles, perf_instret, cpi);
    $display("[TB] branches/jumps=%0d mispredicts=%0d (%.1f%%) load-use stalls=%0d",
             perf_ctrl, perf_mispred,
             (perf_ctrl == 0) ? 0.0 : 100.0 * real'(perf_mispred) / real'(perf_ctrl),
             perf_lu);
  endtask
endmodule
