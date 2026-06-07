module fast_prefix_sum #(
    parameter BM_WIDTH = 128,
    parameter OFF_W = 7
)(
    input logic [BM_WIDTH-1:0] bm_in,
    output logic [BM_WIDTH-1:0][OFF_W-1:0] offset_out,
    output logic [OFF_W:0] pop_count
);

    logic [BM_WIDTH-1:0][OFF_W:0] stage [0:OFF_W];

    genvar i;
    generate
        for (i = 0; i < BM_WIDTH; i++) begin : init_stage
            assign stage[0][i] = {{OFF_W{1'b0}}, bm_in[i]};
        end
    endgenerate

    genvar s;
    generate
        for (s = 1; s <= OFF_W; s++) begin : prefix_stages
            for (i = 0; i < BM_WIDTH; i++) begin : prefix_bits
                if (i >= (1 << (s-1))) begin
                    assign stage[s][i] = stage[s-1][i] + stage[s-1][i - (1 << (s-1))];
                end else begin
                    assign stage[s][i] = stage[s-1][i];
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < BM_WIDTH; i++) begin : gen_offset
            assign offset_out[i] = stage[OFF_W][i][OFF_W-1:0] - {{(OFF_W-1){1'b0}}, bm_in[i]};
        end
    endgenerate

    assign pop_count = stage[OFF_W][BM_WIDTH-1];

endmodule
