module phase_meter 
#(
    parameter WIDTH     = 12    ,
    parameter AVG_BITS  = 20 
)
(
    input  wire             clk         ,
    input  wire             rst_n       ,
    input  wire [WIDTH-1:0] wave_A      ,
    input  wire [WIDTH-1:0] wave_B      ,
    
    output reg  [15:0]      cos_phase   ,
    output reg              data_vld     
);

//θ = arccos( (cos_phase - 1024) / 1024 ) × (180/π)

// --- 1. 动态直流消除 (增强稳定性) ---
reg [AVG_BITS-1:0] dc_cnt;
reg [AVG_BITS+WIDTH-1:0] sum_A, sum_B;
reg signed [WIDTH:0] offset_A, offset_B;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        dc_cnt <= 0; 
        sum_A <= 0; 
        sum_B <= 0;
        offset_A <= 2048; 
        offset_B <= 2048;
    end 
    else begin
        dc_cnt <= dc_cnt + 1'b1;
        sum_A  <= sum_A + wave_A;
        sum_B  <= sum_B + wave_B;
        if(dc_cnt == {AVG_BITS{1'b1}}) begin
            offset_A <= sum_A >> AVG_BITS;
            offset_B <= sum_B >> AVG_BITS;
            sum_A <= 0; sum_B <= 0;
        end
    end
end

// --- 2. 信号去偏置 ---
reg signed [WIDTH:0] s_a, s_b;
always @(posedge clk) begin
    s_a <= $signed({1'b0, wave_A}) - offset_A;
    s_b <= $signed({1'b0, wave_B}) - offset_B;
end

// --- 3. 乘法运算 ---
reg signed [2*WIDTH:0] mult_ab;
reg signed [2*WIDTH:0] mult_aa;
always @(posedge clk) begin
    mult_ab <= s_a * s_b;
    mult_aa <= s_a * s_a;
end

// --- 4. 积分累加  ---
// 截断低位以节省空间：将 25位结果右移 4位再累加，精度损失极小
localparam ACC_WIDTH = (2*WIDTH+1) + AVG_BITS - 4; 
reg [AVG_BITS-1:0] acc_cnt;
reg signed [ACC_WIDTH-1:0] acc_ab, acc_aa;
reg signed [ACC_WIDTH-1:0] final_ab, final_aa;
reg                        div_en;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        acc_cnt <= 0; 
        acc_ab <= 0; 
        acc_aa <= 0; 
        div_en <= 0;
    end 
    else begin
        acc_cnt <= acc_cnt + 1'b1;
        acc_ab  <= acc_ab + (mult_ab >>> 4); 
        acc_aa  <= acc_aa + (mult_aa >>> 4);
        
        if(acc_cnt == {AVG_BITS{1'b1}}) begin
            final_ab <= acc_ab;
            final_aa <= acc_aa;
            div_en   <= 1'b1;
            acc_ab   <= 0; acc_aa <= 0;
        end 
        else
            div_en   <= 1'b0;
    end
end

// --- 5.除法处理 ---
reg signed [63:0] div_pre_res;
reg               div_en_d1, div_en_d2;

always @(posedge clk) begin
    div_en_d1 <= div_en;
    div_en_d2 <= div_en_d1; // 模拟流水线延迟
    if(div_en) begin
        if(final_aa > 50) // 降低阈值提高灵敏度
            div_pre_res <= (final_ab <<< 10) / final_aa;
        else
            div_pre_res <= 0;
    end
end

// --- 6. 最终输出与饱和逻辑 (四级流水) ---
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cos_phase <= 16'd1024; // 复位时设为中间值（90度）
        data_vld <= 0;
    end 
    else begin
        data_vld <= div_en_d2; 
        
        // 将结果加上偏移量 1024，使范围变为 0 到 2048
        // 增加限幅逻辑防止极端情况溢出
        if (div_pre_res + 1024 >= 2048)
            cos_phase <= 16'd2048;
        else if (div_pre_res + 1024 <= 0)
            cos_phase <= 16'd0;
        else
            cos_phase <= div_pre_res[15:0] + 16'sd1024;
    end
end

endmodule
