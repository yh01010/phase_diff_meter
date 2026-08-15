// 相位差检测：
// 1. 估计并去除两路输入波形的直流偏置。
// 2. 累加计算归一化相关系数所需的乘积。
// 3. 计算 cos(theta) = sum(A*B) / sqrt(sum(A*A) * sum(B*B))。
// 4. 将 Q12 格式的余弦值从 [-1, 1] 映射到 [0, 8192]。
module phase_meter
#(
    parameter WIDTH       = 12, // 输入采样数据位宽。
    parameter AVG_BITS    = 20, // 平均窗口大小为 2^AVG_BITS 个采样点。
    parameter ENERGY_MIN  = 50  // 允许进行归一化计算的最小能量阈值。
)
(
    input  wire             clk,       // 系统时钟。
    input  wire             rst_n,     // 低电平有效的异步复位。
    input  wire [WIDTH-1:0] wave_A,    // A 路无符号输入采样值。
    input  wire [WIDTH-1:0] wave_B,    // B 路无符号输入采样值。

    output reg  [15:0]      cos_phase, // 映射后的余弦值，范围为 [0, 8192]。
    output reg              data_vld   // cos_phase 更新时输出一个时钟周期的有效脉冲。
);

// 对应的相位角计算公式为：
// θ = acos((cos_phase - 4096) / 4096) * (180 / PI)

// --- 1. 直流偏置估计 ---
// 对两路输入分别进行 2^AVG_BITS 个采样点的累加和平均。
reg [AVG_BITS-1:0] dc_cnt;
reg [AVG_BITS+WIDTH-1:0] sum_A, sum_B;
reg signed [WIDTH:0] offset_A, offset_B;
wire [AVG_BITS+WIDTH-1:0] sum_A_with_sample;
wire [AVG_BITS+WIDTH-1:0] sum_B_with_sample;

// 计算包含当前采样点在内的累加结果，用于窗口结束时更新偏置。
assign sum_A_with_sample = sum_A + wave_A;
assign sum_B_with_sample = sum_B + wave_B;

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
        if(dc_cnt == {AVG_BITS{1'b1}}) begin
            // 取累加和的高位，相当于除以 2^AVG_BITS，得到平均值。
            offset_A <= {1'b0, sum_A_with_sample[AVG_BITS+WIDTH-1:AVG_BITS]};
            offset_B <= {1'b0, sum_B_with_sample[AVG_BITS+WIDTH-1:AVG_BITS]};
            sum_A <= 0;
            sum_B <= 0;
        end
        else begin
            sum_A <= sum_A + wave_A;
            sum_B <= sum_B + wave_B;
        end
    end
end

// --- 2. 去除输入信号的直流偏置 ---
reg signed [WIDTH:0] s_a, s_b;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s_a <= 0;
        s_b <= 0;
    end
    else begin
        // 先补充符号位，再减去对应通道的直流偏置。
        s_a <= $signed({1'b0, wave_A}) - offset_A;
        s_b <= $signed({1'b0, wave_B}) - offset_B;
    end
end

// --- 3. 乘法运算 ---
// 去直流后的信号宽度为 WIDTH+1 位，乘积使用 2*WIDTH+2 位保存。
reg signed [2*WIDTH+1:0] mult_ab;
reg signed [2*WIDTH+1:0] mult_aa;
reg signed [2*WIDTH+1:0] mult_bb;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mult_ab <= 0;
        mult_aa <= 0;
        mult_bb <= 0;
    end
    else begin
        // 分别计算 A*B、A*A 和 B*B。
        mult_ab <= s_a * s_b;
        mult_aa <= s_a * s_a;
        mult_bb <= s_b * s_b;
    end
end

// --- 4. 乘积累加 ---
// 乘积右移 4 位后再累加，以节省累加器位宽，代价是损失少量低位精度。
localparam ACC_WIDTH = (2*WIDTH+2) + AVG_BITS - 4;
reg [AVG_BITS-1:0] acc_cnt;
reg signed [ACC_WIDTH-1:0] acc_ab, acc_aa, acc_bb;
reg signed [ACC_WIDTH-1:0] final_ab, final_aa, final_bb;
reg                        div_en;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        acc_cnt <= 0;
        acc_ab <= 0;
        acc_aa <= 0;
        acc_bb <= 0;
        final_ab <= 0;
        final_aa <= 0;
        final_bb <= 0;
        div_en <= 0;
    end
    else begin
        acc_cnt <= acc_cnt + 1'b1;
        acc_ab  <= acc_ab + (mult_ab >>> 4);
        acc_aa  <= acc_aa + (mult_aa >>> 4);
        acc_bb  <= acc_bb + (mult_bb >>> 4);

        if(acc_cnt == {AVG_BITS{1'b1}}) begin
            // 保存包含当前乘积在内的完整累加窗口结果。
            final_ab <= acc_ab + (mult_ab >>> 4);
            final_aa <= acc_aa + (mult_aa >>> 4);
            final_bb <= acc_bb + (mult_bb >>> 4);
            div_en   <= 1'b1;
            acc_ab   <= 0;
            acc_aa   <= 0;
            acc_bb   <= 0;
        end
        else
            div_en   <= 1'b0;
    end
end

// --- 5. 能量归一化和迭代开平方 ---
// 归一化公式：
// cos(theta) = final_ab / sqrt(final_aa * final_bb)。
localparam RADICAND_WIDTH  = 2 * ACC_WIDTH;
localparam NUMERATOR_WIDTH = ACC_WIDTH + 12;

wire [ACC_WIDTH-1:0] final_aa_unsigned;
wire [ACC_WIDTH-1:0] final_bb_unsigned;
wire [RADICAND_WIDTH-1:0] energy_product;
assign final_aa_unsigned = final_aa[ACC_WIDTH-1:0];
assign final_bb_unsigned = final_bb[ACC_WIDTH-1:0];
assign energy_product = final_aa_unsigned * final_bb_unsigned;

// 迭代开平方模块的输入、输出和握手信号。
reg  [RADICAND_WIDTH-1:0] sqrt_radicand;
reg                         sqrt_start;
wire                        sqrt_busy;
wire                        sqrt_valid;
wire [ACC_WIDTH-1:0]        sqrt_root;

// 分子左移 12 位，使最终除法结果保持 Q12 定点格式。
reg signed [NUMERATOR_WIDTH-1:0] numerator_q12;
wire signed [ACC_WIDTH:0]        sqrt_root_signed;
reg signed [63:0]                div_pre_res;
reg                              result_valid;
assign sqrt_root_signed = {1'b0, sqrt_root};

integer_sqrt_iterative
#(
    .RADICAND_WIDTH (RADICAND_WIDTH)
) integer_sqrt_inst (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (sqrt_start),
    .radicand  (sqrt_radicand),
    .busy      (sqrt_busy),
    .valid     (sqrt_valid),
    .root      (sqrt_root)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sqrt_radicand <= 0;
        sqrt_start    <= 1'b0;
        numerator_q12 <= 0;
        div_pre_res   <= 0;
        result_valid  <= 1'b0;
    end
    else begin
        // 默认不启动新的开平方操作，避免 start 保持多个时钟周期。
        sqrt_start   <= 1'b0;
        result_valid <= 1'b0;

        if(div_en && !sqrt_busy) begin
            // 当任一路信号能量过小时，不进行归一化，避免结果不稳定。
            if((final_aa_unsigned > ENERGY_MIN) &&
               (final_bb_unsigned > ENERGY_MIN)) begin
                sqrt_radicand <= energy_product;
                numerator_q12 <= {{12{final_ab[ACC_WIDTH-1]}}, final_ab} << 12;
                sqrt_start    <= 1'b1;
            end
        end

        if(sqrt_valid && (sqrt_root != 0)) begin
            // 开平方结果有效后，执行最终的有符号除法。
            div_pre_res  <= numerator_q12 / sqrt_root_signed;
            result_valid <= 1'b1;
        end
    end
end

// --- 6. 最终输出和饱和处理 ---
// 将 Q12 格式的余弦值 [-4096, 4096] 映射为 [0, 8192]。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cos_phase <= 16'd4096; // 复位到中点，对应 cos(theta) = 0。
        data_vld <= 0;
    end
    else begin
        data_vld <= result_valid;

        if(result_valid) begin
            // 对超出 [-1, 1] 的计算结果进行饱和限制。
            if(div_pre_res >= 4096)
                cos_phase <= 16'd8192;
            else if(div_pre_res <= -4096)
                cos_phase <= 16'd0;
            else
                cos_phase <= div_pre_res[15:0] + 16'sd4096;
        end
    end
end

endmodule

// 迭代式整数开平方模块。
// 每个时钟处理被开方数的两位，因此 RADICAND_WIDTH 必须为偶数。
module integer_sqrt_iterative
#(
    parameter RADICAND_WIDTH = 82 // 被开方数位宽，必须为偶数。
)
(
    input  wire                          clk,       // 系统时钟。
    input  wire                          rst_n,     // 低电平有效的异步复位。
    input  wire                          start,     // 开始计算脉冲。
    input  wire [RADICAND_WIDTH-1:0]     radicand,  // 无符号被开方数。
    output reg                           busy,      // 计算进行中标志。
    output reg                           valid,     // 开平方结果有效脉冲。
    output reg  [(RADICAND_WIDTH/2)-1:0] root       // 整数平方根结果。
);

localparam ROOT_WIDTH  = RADICAND_WIDTH / 2;
localparam COUNT_WIDTH = $clog2(ROOT_WIDTH + 1);

// 按位开平方算法的内部状态。
reg [RADICAND_WIDTH-1:0] radicand_shift;
reg [ROOT_WIDTH-1:0]     root_work;
reg [ROOT_WIDTH+1:0]     remainder;
reg [COUNT_WIDTH-1:0]    iteration;

// 单次迭代所需的组合逻辑中间量。
wire [ROOT_WIDTH+1:0] shifted_remainder;
wire [ROOT_WIDTH+1:0] trial_divisor;
wire                  root_bit;
wire [ROOT_WIDTH+1:0] remainder_next;
wire [ROOT_WIDTH-1:0] root_next;

// 部分余数左移两位，并移入被开方数的下一组两位。
assign shifted_remainder = {
    remainder[ROOT_WIDTH-1:0],
    radicand_shift[RADICAND_WIDTH-1:RADICAND_WIDTH-2]
};

// 生成当前迭代的试除数，并判断下一位平方根是否为 1。
assign trial_divisor = {root_work, 2'b01};
assign root_bit = (shifted_remainder >= trial_divisor);
assign remainder_next = root_bit
                      ? shifted_remainder - trial_divisor
                      : shifted_remainder;
assign root_next = {root_work[ROOT_WIDTH-2:0], root_bit};

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        radicand_shift <= 0;
        root_work      <= 0;
        remainder      <= 0;
        iteration      <= 0;
        root           <= 0;
        busy           <= 1'b0;
        valid          <= 1'b0;
    end
    else begin
        // valid 只保持一个时钟周期。
        valid <= 1'b0;

        if(start && !busy) begin
            // 接收新的被开方数，并初始化迭代状态。
            radicand_shift <= radicand;
            root_work      <= 0;
            remainder      <= 0;
            iteration      <= 0;
            busy           <= 1'b1;
        end
        else if(busy) begin
            // 消耗下一组两位输入数据，并生成下一位平方根。
            radicand_shift <= {
                radicand_shift[RADICAND_WIDTH-3:0], 2'b00
            };
            root_work <= root_next;
            remainder <= remainder_next;

            if(iteration == ROOT_WIDTH - 1) begin
                // 最后一位平方根计算完成。
                root  <= root_next;
                busy  <= 1'b0;
                valid <= 1'b1;
            end
            else begin
                iteration <= iteration + 1'b1;
            end
        end
    end
end

endmodule
