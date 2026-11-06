module branch_predictor #(
  parameter int ENTRIES = 64,
  parameter bit ENABLE  = 1'b1
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [31:0] if_pc,
  output logic        pred_taken,
  output logic [31:0] pred_target,

  input  logic        upd_en,
  input  logic [31:0] upd_pc,
  input  logic        upd_is_cond,
  input  logic        upd_taken,
  input  logic [31:0] upd_target
);
  localparam int IDX_W = $clog2(ENTRIES);
  localparam int TAG_W = 32 - IDX_W - 2;

  typedef struct packed {
    logic             valid;
    logic             uncond;
    logic [TAG_W-1:0] tag;
    logic [31:0]      target;
  } btb_entry_t;

  btb_entry_t btb [ENTRIES];
  logic [1:0] bht [ENTRIES];

  logic [IDX_W-1:0] r_idx;
  logic [TAG_W-1:0] r_tag;
  logic             hit;

  assign r_idx = if_pc[IDX_W+1:2];
  assign r_tag = if_pc[31:IDX_W+2];
  assign hit   = btb[r_idx].valid && (btb[r_idx].tag == r_tag);

  assign pred_taken  = ENABLE && hit && (btb[r_idx].uncond || bht[r_idx][1]);
  assign pred_target = btb[r_idx].target;

  logic [IDX_W-1:0] u_idx;
  logic [TAG_W-1:0] u_tag;
  assign u_idx = upd_pc[IDX_W+1:2];
  assign u_tag = upd_pc[31:IDX_W+2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < ENTRIES; i++) begin
        btb[i] <= '0;
        bht[i] <= 2'b01;  // weakly not-taken
      end
    end else if (upd_en) begin
      if (upd_is_cond) begin
        if (upd_taken  && bht[u_idx] != 2'b11) bht[u_idx] <= bht[u_idx] + 2'd1;
        if (!upd_taken && bht[u_idx] != 2'b00) bht[u_idx] <= bht[u_idx] - 2'd1;
      end

      if (upd_taken) begin
        btb[u_idx].valid  <= 1'b1;
        btb[u_idx].uncond <= !upd_is_cond;
        btb[u_idx].tag    <= u_tag;
        btb[u_idx].target <= upd_target;

        // a branch seen for the first time starts as weakly taken
        if (upd_is_cond && !(btb[u_idx].valid && btb[u_idx].tag == u_tag))
          bht[u_idx] <= 2'b10;
      end
    end
  end
endmodule
