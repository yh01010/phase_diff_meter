module spi
#(
    parameter  width = 'd32 ,  //数据传输位数
    parameter  depth = 'd8     //数据传输个数
)
(	
    input   wire            clk             ,
	input   wire            rst_n           ,
	input   wire            CS_N            ,
	input   wire            SCK             ,
	input   wire            MOSI            ,  //FPGA数据输入
    input   wire    [31:0]  sending_data0   ,
    input   wire    [31:0]  sending_data1   ,
    input   wire    [31:0]  sending_data2   ,
    input   wire    [31:0]  sending_data3   ,
    input   wire    [31:0]  sending_data4   ,
    input   wire    [31:0]  sending_data5   ,
    input   wire    [31:0]  sending_data6   ,
    input   wire    [31:0]  sending_data7   ,
    
    output  reg 			MISO            ,  //FPGA数据输出
    output  reg             mark            ,  //单个数据传输完成标志
    output  reg             end_mark        ,  //整体传输完成标志
    output  reg     [31:0]  receive_data0   ,
    output  reg     [31:0]  receive_data1   ,
    output  reg     [31:0]  receive_data2   ,
    output  reg     [31:0]  receive_data3   ,
    output  reg     [31:0]  receive_data4   ,
    output  reg     [31:0]  receive_data5   ,
    output  reg     [31:0]  receive_data6   ,
    output  reg     [31:0]  receive_data7   
);	
//SPI数据发送宽度和深度的定义
//根据实际收发数据的宽度和深度定义width和depth

parameter  total_width = width*depth-'d1;//数据传输总宽度
reg   [total_width:0]  txd_data;//总发送位宽=width*depth-1；
reg   [total_width:0]  rxd_data;//总接收位宽=width*depth-1；

//数据按位拼接寄存器
//根据实际收发数据的深度注释或开启对应的项
always@(posedge clk or negedge rst_n)begin
if(!rst_n)
    txd_data <= 'd0;
else begin
        txd_data[width-1:0]     <= sending_data0;
        // txd_data[width*'d2-1:width*'d1] <= sending_data1;
        // txd_data[width*'d3-1:width*'d2] <= sending_data2;
        // txd_data[width*'d4-1:width*'d3] <= sending_data3;
        // txd_data[width*'d5-1:width*'d4] <= sending_data4;
        // txd_data[width*'d6-1:width*'d5] <= sending_data5;
        // txd_data[width*'d7-1:width*'d6] <= sending_data6;
        // txd_data[width*'d8-1:width*'d7] <= sending_data7;
        
        // 接收数据（8个，与发送对应）
        receive_data0 <= rxd_data[ width*(depth-0) - 1 : width*(depth-0-1) ];
        // receive_data1 <= rxd_data[ width*(depth-1) - 1 : width*(depth-1-1) ];
        // receive_data2 <= rxd_data[ width*(depth-2) - 1 : width*(depth-2-1) ];
        // receive_data3 <= rxd_data[ width*(depth-3) - 1 : width*(depth-3-1) ];
        // receive_data4 <= rxd_data[ width*(depth-4) - 1 : width*(depth-4-1) ];
        // receive_data5 <= rxd_data[ width*(depth-5) - 1 : width*(depth-5-1) ];
        // receive_data6 <= rxd_data[ width*(depth-6) - 1 : width*(depth-6-1) ];
        // receive_data7 <= rxd_data[ width*(depth-7) - 1 : width*(depth-7-1) ];

    end
end

//************************片选控制信号数据输入及消抖********************
reg   CS_N1,CS_N2;
wire  CS_N_n;
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
    CS_N1 <= 'd0;
    CS_N2 <= 'd0;
    end 
else begin
    CS_N1 <= CS_N;
    CS_N2 <= CS_N1;
    end 
end
assign CS_N_n = (~CS_N1 & CS_N2)? 1'b1:1'b0; //捕捉下降沿
assign CS_N_p = (CS_N1 & ~CS_N2)? 1'b1:1'b0; //捕捉上升沿

//--------------捕获 sck--------------
reg sck_r0,sck_r1,sck_r2;//打三拍
wire sck_n,sck_p;
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
    sck_r0 <= 1'b0; 
    sck_r1 <= 1'b0;
    sck_r2 <= 1'b0;
    end
else if(CS_N2)begin
    sck_r0 <= 1'b0; 
    sck_r1 <= 1'b0;
    sck_r2 <= 1'b0;
    end
else begin
    sck_r0 <= SCK;
    sck_r1 <= sck_r0;
    sck_r2 <= sck_r1;
    end
end
assign sck_n = (~sck_r1 & sck_r2)? 1'b1:1'b0; //捕捉下降沿
assign sck_p = (sck_r1 & ~sck_r2)? 1'b1:1'b0; //捕捉上升沿

//spi数据循环收发
//接收和发送同时进行，依赖同一触发源，下降沿后三个时钟周期，确保介于下降沿于上升沿之间
reg  [31:0]   width_cnt           ;//移位计数器
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
    rxd_data <='d0;
    end
else if(sck_n && !end_mark)begin//下降沿打三拍发送数据同时对方已经发送完成，FPGA已经可以接收数据了
    MISO = txd_data[width_cnt];
    rxd_data[width_cnt] = MOSI;
end
end

always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        width_cnt <= total_width;
    end
    else if (CS_N_n) begin // 片选下降沿，开始新传输
        width_cnt <= total_width;
    end
    else if(sck_n) begin // SCK上升沿，传输一位
        if (width_cnt > 0) begin
            width_cnt <= width_cnt - 1;
        end
        // 当计数器为0时，保持0，不再减少
    end
end

// spi数据接收结束标志信号
// mark为单个数据传输完成标志位
// end_mark为整体数据发送完成标志位
reg [31:0] width_cnt_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        width_cnt_r <= total_width;  // 初始化为total_width
    else 
        width_cnt_r <= width_cnt;
end

// 生成mark信号（每个数据包传输完成）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mark <= 1'b0;
    else if (sck_n && (width_cnt % width == 0) && (width_cnt != total_width))
        mark <= 1'b1;
    else
        mark <= 1'b0;
end

// 生成end_mark信号（整体传输完成）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        end_mark <= 1'b0;
    else if (sck_n && (width_cnt == 0))  // 在最后一个bit传输时产生end_mark
        end_mark <= 1'b1;
    else
        end_mark <= 1'b0;
end

endmodule
