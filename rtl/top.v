module top
(
    input   wire                    clk         , //时钟(采样时钟)
    input   wire                    rst_n       , //复位信号
    input   wire                    dco         , //数据同步时钟
    input   wire    signed  [11:0]  data_in     , //AD数据输入
    input   wire                    CS_N        ,
    input   wire                    SCK         ,
    input   wire                    MOSI        ,
        
    output  wire                    AD9233_clk  , //输出到AD9233的时钟
    output  wire                    pwd_n       , //电源使能 1：ADC断电     0：ADC正常工作
    output  wire                    oeb_n       , //时钟使能 1：关闭输出时钟  0：开启输出时钟   
    output  wire                    AD_sclk     , //SPI_SCLK
    output  wire                    AD_cs_n     , //SPI_CS
    output  wire                    AD_mosi     , //SPI数据线
    output  wire                    MISO
);

wire    signed  [11:0]  data_out;
wire    [11:0]  us_data;
wire    resultl;
wire    clk_stand;
wire    [31:0]  cnt_stand_reg;
wire    [31:0]  cnt_test_reg;

assign us_data = data_out + 'd2048;

AD9233
#(
    .VERF_SEL (2'd3)   //设置参考电压
)AD9233_inst
(
    .clk         (clk        ), //时钟(采样时钟)
    .rst_n       (rst_n      ), //复位信号
    .dco         (dco        ), //数据同步时钟
    .data_in     (data_in    ), //AD数据输入
                  
    .AD9233_clk  (AD9233_clk ), //输出到AD9233的时钟
    .pwd_n       (pwd_n      ), //电源使能 1：ADC断电     0：ADC正常工作
    .oeb_n       (oeb_n      ), //时钟使能 1：关闭输出时钟  0：开启输出时钟   
    .AD_sclk     (AD_sclk    ), //SPI_SCLK
    .AD_cs_n     (AD_cs_n    ), //SPI_CS
    .AD_mosi     (AD_mosi    ), //SPI数据线
    .data_out    (data_out   )
);

comparator  //比较器模块
#(
    .LIMIT ('d2048)    //比较阈值
)comparator_inst
(
    .clk     (clk     ),  //系统时钟
    .rst_n   (rst_n   ),  //复位信号
    .data_in (us_data ),  //数据输入
              
    .result  (result  )   //比较结果
);

freq_meter freq_meter_inst
(
    .sys_clk         (clk),   //系统时钟,50MHz
    .sys_rst_n       (rst_n),   //复位信号
    .clk_test        (result),   //待检测时钟
    .clk_stand       (clk_stand),   //标准时钟,100MHz
    
    .cnt_stand_reg   (cnt_stand_reg),   //闸门内标准时钟周期数
    .cnt_test_reg    (cnt_test_reg),   //闸门内待检测时钟周期数
    .measure_done    ()    //测量完成标志 
);

phase_meter phase_meter_inst
(
    .clk         (clk),  //时钟信号
    .rst_n       (rst_n),  //复位信号
    .signal_test (result),  //待检测的信号
    
    .time_cnt_reg()   //时间计数器
);

spi
#(
    .width ('d32)  ,  //数据传输位数
    .depth ('d2 )     //数据传输个数
)spi_inst
(	
    .clk			(clk	)    ,
	.rst_n		    (rst_n	),
	.CS_N		    (CS_N	),
	.SCK			(SCK	)    ,
	.MOSI		    (MOSI	),  //FPGA数据输入
    .sending_data0  () ,
    .sending_data1  () ,
    .sending_data2  () ,
    .sending_data3  () ,
    .sending_data4  () ,
    .sending_data5  () ,
    .sending_data6  () ,
    .sending_data7  () ,
    
    .MISO		    (MISO),  //FPGA数据输出
    .mark           () ,  //单个数据传输完成标志
    .end_mark       () ,  //整体传输完成标志
    .receive_data0  () ,
    .receive_data1  () ,
    .receive_data2  () ,
    .receive_data3  () ,
    .receive_data4  () ,
    .receive_data5  () ,
    .receive_data6  () ,
    .receive_data7  () 
);	

endmodule
