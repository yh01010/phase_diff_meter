module spi_driver
(	
    input    [15:0]     tx_data      , // 发送数据缓冲区
    output reg [15:0]   rx_data      , // 接收数据缓冲区
    input               clk          , // 系统时钟
    input               rstn         , // 复位信号
    input               CS_N         , // 片选信号
    input               CS_N_n       , // 片选信号下降沿
    input               CS_N_p       , // 片选信号上升沿
    input               sck_n        , // 时钟信号下降沿
    input               sck_p        , // 时钟信号上升沿
    input               SCK          , // 时钟信号
    input               MOSI         , // 主发从收数据线
    output reg          MISO         , // 主收从发数据线
    output reg          mark         , // 16bit数据传输完成标志  
    output              end_mark
);

parameter WIDTH = 15; // 重命名WIDRH为WIDTH，值15表示16位（0-15）

// spi 16bit数据收发
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        MISO <= 1'bz; // 添加MISO复位
    end
    else if (sck_p && !CS_N) begin
        // 只在width_cnt有效时（0-15）更新数据
        if (width_cnt_p <= WIDTH) begin
            MISO <= tx_data[width_cnt_p];
        end
        else if (CS_N) begin // CS_N 无效时
            MISO <= 1'bz; // 高阻（若引脚配置为开漏），或 1'b1（固定电平）
        end
    end
end

// spi 16bit数据收发
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        rx_data <= 'd0;
    end
    else if (sck_n && !CS_N) begin
        // 只在width_cnt有效时（0-15）更新数据
        if (width_cnt_n <= WIDTH) begin
            rx_data[width_cnt_n] <= MOSI;
        end
    end
end

reg [3:0]   width_cnt_n;
reg [3:0]   width_cnt_p;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        width_cnt_n <= 15; // 初始设为无效值（16）
    end
    else if(CS_N_p) begin
        width_cnt_n <= 15;
    end
    else if (sck_n && !CS_N) begin // SCK下降沿
        if (width_cnt_n > 0) begin
            width_cnt_n <= width_cnt_n - 1;
        end
        else if (width_cnt_n == 0) begin
            width_cnt_n <= 15; // 传输完成后设为无效值，避免覆盖
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        width_cnt_p <= 15; // 初始设为无效值（16）
    end
    else if(CS_N_p) begin
        width_cnt_p <= 15;
    end
    else if (sck_p && !CS_N) begin // SCK下降沿
        if (width_cnt_p > 0) begin
            width_cnt_p <= width_cnt_p - 1;
        end
        else if (width_cnt_p == 0) begin
            width_cnt_p <= 15; // 传输完成后设为无效值，避免覆盖
        end
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        mark <= 1'b0;
    end
    else if (width_cnt_p == 0 && sck_p && !CS_N) begin
        mark <= 1'b1; // width_cnt从1到0时置高
    end
    else begin
        mark <= 1'b0;
    end
end

endmodule

module spi_top #(
    parameter width = 32, // 单帧数据宽度（16的整数倍）
    parameter depth = 8   // width位宽数据的数量
)
(	
    output reg [width*depth-1:0] receive_data, // 输出接收数据
    input      [width*depth-1:0] sending_data, // 输入发送数据
    input               clk         , // 系统时钟
    input               rstn        , // 复位信号
    input               CS_N        , // 片选信号
    input               SCK         , // 时钟信号
    input               MOSI        , // 主发从收数据线
    output wire         MISO        , // 主收从发数据线
    output wire         mark        , // 16bit数据传输完成标志
    output reg          end_mark      // 整体传输完成标志
);

// 计算本地参数
localparam total_bits = width * depth; // 总数据位宽
localparam blocks_per_width = width / 16; // 每个width包含的16bit块数量
localparam block_cnt_width = $clog2(blocks_per_width); // 块计数器位宽
localparam frame_cnt_width = $clog2(depth);             // 帧计数器位宽

// 计数器定义
reg [blocks_per_width:0] block_cnt; // 16bit块计数器（计数到blocks_per_width）
reg [depth:0] frame_cnt; // width位宽数据计数器（计数到depth）

reg [1:0] CS_N_filter; // 2级滤波
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        CS_N_filter <= 2'b11;
    end
    else begin
        CS_N_filter <= {CS_N_filter[0], CS_N};
    end
end

reg CS_N_stable;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        CS_N_stable <= 1'b1;
    end
    else begin
        if(CS_N_filter == 'b00) begin
            CS_N_stable <= 0;
        end
        else if(CS_N_filter == 'b11) begin
            CS_N_stable <= 1;
        end
    end
end

// 片选控制信号边沿捕捉
reg CS_N1, CS_N2;
wire CS_N_n, CS_N_p;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        CS_N1 <= 'd0;
        CS_N2 <= 'd0;
    end 
    else begin
        CS_N1 <= CS_N_stable;
        CS_N2 <= CS_N1;
    end 
end
assign CS_N_n = (~CS_N1 & CS_N2) ? 1'b1 : 1'b0; // 下降沿
assign CS_N_p = (CS_N1 & ~CS_N2) ? 1'b1 : 1'b0; // 上升沿

// SCK时钟信号边沿捕捉
reg sck_r0, sck_r1;
wire sck_n, sck_p;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        sck_r0 <= 1'b0; 
        sck_r1 <= 1'b0;
    end
    else if (CS_N_stable) begin  // 片选无效时复位
        sck_r0 <= 1'b1; 
        sck_r1 <= 1'b1;
    end
    else begin
        sck_r0 <= SCK;
        sck_r1 <= sck_r0;
    end
end
assign sck_n = (~sck_r0 & sck_r1) ? 1'b1 : 1'b0; // 下降沿
assign sck_p = (sck_r0 & ~sck_r1) ? 1'b1 : 1'b0; // 上升沿

// 发送数据锁存与移位
wire [15:0] tx_data;
wire [15:0] rx_data;
reg [total_bits-1:0] sending_data_latch; // 使用total_bits

// 锁存和移位发送数据
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        sending_data_latch <= 'd0;
    end
    else begin
        if (CS_N_n) begin    // CS下降沿，锁存发送数据
            sending_data_latch <= sending_data;
        end
        else if (mark) begin  // 每完成16bit传输，左移16位
            sending_data_latch <= sending_data_latch << 16;
        end
    end
end

assign tx_data = sending_data_latch[total_bits-1:total_bits-1-16];  // 取高16位发送

// 接收数据锁存
reg [total_bits-1:0] receive_data_latch; // 使用total_bits
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        receive_data_latch <= 'd0;
    end
    else if (mark) begin
        // 当total_bits < 16时，[total_bits-1:16]为空，{rx_data, ...} 简化为rx_data
        receive_data_latch <= {receive_data_latch[total_bits-1-16:0],rx_data};
    end
    else if(end_mark) begin
        receive_data_latch <= 'd0;
    end
end

// 16bit块计数器（计数每个width包含的块数）
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        block_cnt <= 'd0;
    end
    else if (CS_N_n || frame_cnt == depth) begin  // 新传输开始或传输完成时复位
        block_cnt <= 'd0;
    end
    else if (mark) begin  // 每完成一个16bit块，计数器加1
        if (block_cnt < blocks_per_width - 1) begin
            block_cnt <= block_cnt + 1;
        end
        else begin  // 完成一个width的传输，复位块计数器
            block_cnt <= 'd0;
        end
    end
end

// width位宽数据计数器（计数到depth）
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        frame_cnt <= 'd0;
    end
    else if (CS_N_n) begin  // 新传输开始，复位计数器
        frame_cnt <= 'd0;
    end
    // 每完成一个width的传输（块计数器溢出时），帧计数器加1
    else if (mark && block_cnt == blocks_per_width - 1) begin
        if (frame_cnt < depth - 1) begin
            frame_cnt <= frame_cnt + 1;
        end
        else begin
            frame_cnt <= 'd0; // 完成所有帧后复位
        end
    end
end

// 生成end_mark信号（当传输完depth个width位宽数据时）
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        end_mark <= 1'b0;
    end
    else begin
        // 当最后一个width传输完成且帧计数器达到depth-1时
        end_mark <= (mark && block_cnt == blocks_per_width - 1 && frame_cnt == depth - 1) ? 1'b1 : 1'b0;
    end
end

// 当end_mark有效时，锁存最终接收数据
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        receive_data <= 'd0;
    end
    else if (end_mark) begin  // 整体传输完成，更新接收数据寄存器
        receive_data <= receive_data_latch;
    end
end

spi_driver spi_driver_inst (
    .tx_data      (tx_data),
    .rx_data      (rx_data),
    .clk          (clk),
    .rstn         (rstn),
    .CS_N         (CS_N_stable),
    .CS_N_n       (CS_N_n),
    .CS_N_p       (CS_N_p),
    .sck_n        (sck_n),
    .sck_p        (sck_p),
    .SCK          (SCK),
    .MOSI         (MOSI),
    .MISO         (MISO),
    .mark         (mark)
);

endmodule
