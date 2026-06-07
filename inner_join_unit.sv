module inner_join_unit #(
    parameter BM_WIDTH = 128,
    parameter OFF_W = 7,
    parameter W_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter T = 4,
    parameter N_ADDERS = 8,
    parameter FIFO_DEPTH = 128
)(
    input logic clk,
    input logic rst_n,
    input logic start_i,
    input logic [BM_WIDTH-1:0] bm_a,
    input logic [BM_WIDTH-1:0] bm_b,
    input logic [W_WIDTH-1:0] fiber_b_data [0:BM_WIDTH-1],
    input logic [T-1:0] fiber_a_data [0:BM_WIDTH-1],
    output logic [T-1:0][ACC_WIDTH-1:0] result,
    output logic done_o
);

    typedef enum logic [2:0] {
        IDLE, SCAN, WAIT_LAGGY, CORRECT, DONE_ST
    } state_t;

    state_t state;

    logic [BM_WIDTH-1:0] and_result;
    assign and_result = bm_a & bm_b;

    logic [BM_WIDTH-1:0][OFF_W-1:0] fast_offset_b;
    logic [OFF_W:0] fast_popcount_b;

    fast_prefix_sum #(
        .BM_WIDTH(BM_WIDTH),
        .OFF_W(OFF_W)
    ) u_fast (
        .bm_in(bm_b),
        .offset_out(fast_offset_b),
        .pop_count(fast_popcount_b)
    );

    logic [BM_WIDTH-1:0][OFF_W-1:0] laggy_offset_a;
    logic [OFF_W:0] laggy_popcount_a;
    logic laggy_done;

    laggy_prefix_sum #(
        .BM_WIDTH(BM_WIDTH),
        .N_ADDERS(N_ADDERS),
        .OFF_W(OFF_W)
    ) u_laggy (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .bm_in(bm_a),
        .offset_out(laggy_offset_a),
        .pop_count(laggy_popcount_a),
        .done_o(laggy_done)
    );

    logic [OFF_W-1:0] fifo_mp_rdata;
    logic fifo_mp_empty, fifo_mp_full;
    logic fifo_mp_wr, fifo_mp_rd;
    logic [OFF_W-1:0] fifo_mp_wdata;

    fifo #(
        .WIDTH(OFF_W),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo_mp (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(fifo_mp_wr),
        .wr_data(fifo_mp_wdata),
        .full(fifo_mp_full),
        .rd_en(fifo_mp_rd),
        .rd_data(fifo_mp_rdata),
        .empty(fifo_mp_empty)
    );

    logic [W_WIDTH-1:0] fifo_b_rdata;
    logic fifo_b_empty, fifo_b_full;
    logic fifo_b_wr, fifo_b_rd;
    logic [W_WIDTH-1:0] fifo_b_wdata;

    fifo #(
        .WIDTH(W_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo_b (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(fifo_b_wr),
        .wr_data(fifo_b_wdata),
        .full(fifo_b_full),
        .rd_en(fifo_b_rd),
        .rd_data(fifo_b_rdata),
        .empty(fifo_b_empty)
    );

    logic [T-1:0][ACC_WIDTH-1:0] pseudo_acc;
    logic [T-1:0][ACC_WIDTH-1:0] corr_acc;
    logic [OFF_W:0] scan_idx;
    logic [OFF_W:0] corr_total;
    logic [OFF_W:0] corr_ptr;

    integer t;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            scan_idx <= '0;
            corr_total <= '0;
            corr_ptr <= '0;
            done_o <= 1'b0;
            fifo_mp_wr <= 1'b0;
            fifo_b_wr <= 1'b0;
            fifo_mp_rd <= 1'b0;
            fifo_b_rd <= 1'b0;
            for (t = 0; t < T; t++) begin
                pseudo_acc[t] <= '0;
                corr_acc[t] <= '0;
                result[t] <= '0;
            end
        end else begin
            fifo_mp_wr <= 1'b0;
            fifo_b_wr <= 1'b0;
            fifo_mp_rd <= 1'b0;
            fifo_b_rd <= 1'b0;
            done_o <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_i) begin
                        scan_idx <= '0;
                        corr_total <= '0;
                        corr_ptr <= '0;
                        for (t = 0; t < T; t++) begin
                            pseudo_acc[t] <= '0;
                            corr_acc[t] <= '0;
                        end
                        state <= SCAN;
                    end
                end

                SCAN: begin
                    if (scan_idx < BM_WIDTH) begin
                        if (and_result[scan_idx]) begin
                            fifo_mp_wr <= 1'b1;
                            fifo_mp_wdata <= scan_idx[OFF_W-1:0];
                            fifo_b_wr <= 1'b1;
                            fifo_b_wdata <= fiber_b_data[fast_offset_b[scan_idx]];
                            for (t = 0; t < T; t++)
                                pseudo_acc[t] <= pseudo_acc[t] +
                                    {{(ACC_WIDTH-W_WIDTH){fiber_b_data[fast_offset_b[scan_idx]][W_WIDTH-1]}},
                                     fiber_b_data[fast_offset_b[scan_idx]]};
                            corr_total <= corr_total + 1;
                        end
                        scan_idx <= scan_idx + 1;
                    end else begin
                        if (laggy_done)
                            state <= (corr_total == '0) ? DONE_ST : CORRECT;
                        else
                            state <= WAIT_LAGGY;
                    end
                end

                WAIT_LAGGY: begin
                    if (laggy_done)
                        state <= (corr_total == '0) ? DONE_ST : CORRECT;
                end

                CORRECT: begin
                    if (!fifo_mp_empty && !fifo_b_empty) begin
                        for (t = 0; t < T; t++) begin
                            if (!fiber_a_data[laggy_offset_a[fifo_mp_rdata]][t])
                                corr_acc[t] <= corr_acc[t] +
                                    {{(ACC_WIDTH-W_WIDTH){fifo_b_rdata[W_WIDTH-1]}},
                                     fifo_b_rdata};
                        end
                        fifo_mp_rd <= 1'b1;
                        fifo_b_rd <= 1'b1;
                        corr_ptr <= corr_ptr + 1;
                        if (corr_ptr == corr_total - 1)
                            state <= DONE_ST;
                    end
                end

                DONE_ST: begin
                    for (t = 0; t < T; t++)
                        result[t] <= pseudo_acc[t] - corr_acc[t];
                    done_o <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
