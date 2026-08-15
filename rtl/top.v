module top
(
    input   wire            clk         ,  //系统时钟
    input   wire            rst_n       ,  //复位信号
    input   wire    [11:0]  data_in_A   ,  //通道A数据输入
    input   wire    [11:0]  data_in_B   ,  //通道B数据输入
    input                           CS_N        , // 片选信号
    input                           SCK         , // 时钟信号
    input                           MOSI        , // 主发从收数据线
    
    output wire                     MISO        , // 主收从发数据线
    output  wire            clk_A       ,  //输出到A通道的时钟
    output  wire            clk_B          //输出到B通道的时钟
);

wire    [11:0]  data_out_A;
wire    [11:0]  data_out_B;
wire    [11:0]  pll_200m;
wire    [15:0]  cos_phase;
wire    [31:0]  sending_data;
wire    [31:0]  receive_data1;
wire    [31:0]  receive_data2;
wire    [31:0]  receive_data3;
wire    [31:0]  receive_data4;

assign sending_data = {16'b0,cos_phase};

pll	pll_inst (
	.areset ( !rst_n ),
	.inclk0 ( clk ),
	.c0 ( pll_200m )
	);

AD9226  AD9226_inst
(
    .clk         (clk      ),  //系统时钟
    .rst_n       (rst_n    ),  //复位信号
    .data_in_A   (data_in_A),  //通道A数据输入
    .data_in_B   (data_in_B),  //通道B数据输入
             
    .clk_A       (clk_A     ),  //输出到A通道的时钟
    .clk_B       (clk_B     ),  //输出到B通道的时钟
    .data_out_A  (data_out_A),  //通道A处理后数据输出
    .data_out_B  (data_out_B)   //通道B处理后数据输出
);

phase_meter 
#(
    .WIDTH      (12)     ,
    .AVG_BITS   (25)  
)phase_meter_inst
(
    .clk         (clk  ),
    .rst_n       (rst_n),
    .wave_A      (data_out_A),
    .wave_B      (data_out_B),
    
    .cos_phase   (cos_phase),
    .data_vld    () 
);

spi_top #(
    .width (32) , // 单帧数据宽度（16的整数倍）
    .depth (1 )   // width位宽数据的数量
)spi_top_inst
(	
    .receive_data({
                    receive_data1
                    }), // 输出接收数据
    .sending_data({
                  sending_data 
                  }), // 输入发送数据
    .clk         (pll_200m ), // 系统时钟
    .rstn        (rst_n), // 复位信号
    .CS_N        (CS_N), // 片选信号
    .SCK         (SCK ), // 时钟信号
    .MOSI        (MOSI), // 主发从收数据线
    .MISO        (MISO), // 主收从发数据线
    .mark        (), // 16bit数据传输完成标志
    .end_mark    ()  // 整体传输完成标志
);

// spi
// #(
    // .width ('d32)  ,  //数据传输位数
    // .depth ('d4 )     //数据传输个数
// )spi_inst
// (	
    // .clk             (clk  ),
	// .rst_n           (rst_n),
	// .CS_N            (CS_N ),
	// .SCK             (SCK),
	// .MOSI            (MOSI),  //FPGA数据输入
    // .sending_data0   (sending_data),
    // .sending_data1   ('d0),
    // .sending_data2   ('d0),
    // .sending_data3   ('d0),
    // .sending_data4   (),
    // .sending_data5   (),
    // .sending_data6   (),
    // .sending_data7   (),
    
    // .MISO            (MISO),  //FPGA数据输出
    // .mark            (),  //单个数据传输完成标志
    // .end_mark        (),  //整体传输完成标志
    // .receive_data0   (),
    // .receive_data1   (),
    // .receive_data2   (),
    // .receive_data3   (),
    // .receive_data4   (),
    // .receive_data5   (),
    // .receive_data6   (),
    // .receive_data7   ()
// );	

endmodule
