module AD9233
#(
    parameter VERF_SEL = 2'd3  //设置参考电压
)
(
    input   wire                    clk         , //时钟(采样时钟)
    input   wire                    rst_n       , //复位信号
    input   wire                    dco         , //数据同步时钟
    input   wire    signed  [11:0]  data_in     , //AD数据输入
        
    output  wire                    AD9233_clk  , //输出到AD9233的时钟
    output  wire                    pwd_n       , //电源使能 1：ADC断电     0：ADC正常工作
    output  wire                    oeb_n       , //时钟使能 1：关闭输出时钟  0：开启输出时钟   
    output  wire                    AD_sclk     , //SPI_SCLK
    output  wire                    AD_cs_n     , //SPI_CS
    output  wire                    AD_mosi     , //SPI数据线
    output  reg     signed  [11:0]  data_out
);

// 内部时钟版本代码
// Volt = DATA * ( VREF / 4096 ) , VREF = 1.25V 或 1.5V 或 1.75V 或者2.0V通过SPI配置 , DATA范围 -2048-2047，输入不带衰减
// Volt = DATA * ( VREF * 10 / 4096 ) , DATA范围 -2048-2047，输入带衰减10倍

// 芯片的SCLK上升沿芯片进行数据读取，所以在下降沿需要对数据进行更新移动位置
localparam delay_100ms = ( 50_000_000 / 10 ) - 1;
localparam sclk_cnt    = ( 24 * 2 ) - 1;
// 芯片的寄存器如下所示，见芯片手册的32页 - 
localparam Modes         = 8'h08 ; // 模式寄存器
localparam Clock         = 8'h09 ; // 全局时钟寄存器
localparam Offset_adjust = 8'h10 ; // 偏移调整寄存器
localparam Output_mode   = 8'h14 ; // 输出模式寄存器
localparam OUTPUT_PHASE  = 8'h16 ; // 输出相位调节

localparam VREF_REG      = 8'h18 ; // 参考电压配置
localparam Transfer      = 8'hFF ;
localparam VERF_1_25V    = 2'b00 ; // 参考电压1.25V
localparam VERF_1_50V    = 2'b01 ; // 参考电压1.5V
localparam VERF_1_75V    = 2'b10 ; // 参考电压1.75V
localparam VERF_2_00V    = 2'b11 ; // 参考电压2.0V

localparam READ  = 1'b1;
localparam WRITE = 1'b0;

localparam DCO_Inverted  = 1'b1;
localparam DCO_Normal    = 1'b0;

localparam DATA_Invert    = 1'b1;
localparam DATA_Invert_no = 1'b0;

localparam data_unsigned = 2'b00;
localparam data_signed   = 2'b01;

reg          cs_n       ;
reg          sclk       ;
reg          mosi       ;
wire         cs_nege    ;
wire         sclk_nege  ;
reg  [2:0]   spi_state  ;
reg          sclk_reg   ;
reg          cs_reg     ;
reg  [23:0]  spi_data   ;
reg  [23:0]  send_data  ;
reg  [1:0]   dat_state  ;
reg  [23:0]  delay_cnt  ;
reg          VERF       ;
 

assign pwd_n = 1'b0;  //0=ADC正常工作（上电）
assign oeb_n = 1'b0;  //0=开启输出时钟（数据正常输出）
assign AD9233_clk = clk;

always @(*) begin
    case(VERF_SEL)
        2'd0:VERF = VERF_1_25V;
        2'd1:VERF = VERF_1_50V;
        2'd2:VERF = VERF_1_75V;
        2'd3:VERF = VERF_2_00V;
        default:VERF = VERF_2_00V; 
    endcase
end

// 需要写入的数据
always@(*)begin
    case(dat_state)
        2'd0 : send_data = {WRITE,2'b00,5'd0,Output_mode  ,2'b00,1'b0,1'b0,1'b0,DATA_Invert_no,data_signed};  // 打开ADC双边沿模式（交错模式）
        2'd1 : send_data = {WRITE,2'b00,5'd0,OUTPUT_PHASE ,DCO_Normal,7'd0};  // DCO配置不反向
        2'd2 : send_data = {WRITE,2'b00,5'd0,VREF_REG     ,VERF,6'd0};  // 设置VREF电压
        2'd3 : send_data = {WRITE,2'b00,5'd0,Transfer     ,7'd0 ,1'b1 };  // 寄存器数据传输
    default:send_data = 24'd0;
  endcase
end

// SPI时序控制器
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
        cs_n <= 1'b1;
        sclk <= 1'b1;
        dat_state <= 2'd0 ;
        delay_cnt <= 24'd0;
        spi_state <= 3'd0 ;
    end
    else begin
        case(spi_state)
            3'd0:begin  // 初始化IO口
                cs_n <= 1'b1;
                sclk <= 1'b1;
                dat_state <= 2'd0 ;
                if(delay_cnt >= delay_100ms)begin
                    delay_cnt <= 24'd0;
                    spi_state <= 3'd1 ;
                end
                else begin
                    delay_cnt <= delay_cnt + 1'b1;
                    spi_state <= 3'd0 ;
                end
            end
            3'd1:begin
                cs_n <= 1'b1;
                sclk <= 1'b1;
                spi_state <= 3'd2 ;
            end
            3'd2:begin
                cs_n  <= 1'b0;
                spi_state <= 3'd3 ;
            end
            3'd3:begin
                sclk <= ~sclk;
                if(delay_cnt >= sclk_cnt)begin
                    delay_cnt <= 24'd0;
                    spi_state <= 3'd4 ;
                end
                else begin
                    delay_cnt <= delay_cnt + 1'b1;
                    spi_state <= 3'd3 ;
                end
            end
            3'd4:begin
                sclk <= 1'b1;
                spi_state <= 3'd5 ;
            end
            3'd5:begin
                cs_n <= 1'b1;
                if(dat_state == 2'd3)begin
                    dat_state <= 2'd3;
                    spi_state <= 3'd5;
                end
                else begin
                    dat_state <= dat_state + 1'b1;
                    spi_state <= 3'd1;
                end
            end
            default:spi_state <= 3'd0;
        endcase
    end
end

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
        cs_reg   <= 1'b0;
        sclk_reg <= 1'b0;
    end
    else begin
        cs_reg   <= cs_n;
        sclk_reg <= sclk;
    end
end

assign cs_nege   = ( ~cs_n ) & cs_reg   ;
assign sclk_nege = ( ~sclk ) & sclk_reg ;

// 对数据进行移位处理
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
        mosi <= 1'b0;
        spi_data <= 16'd0;
    end
    else if(cs_nege == 1'b1)begin
        mosi <= 1'b0;
        spi_data <= send_data;
    end
    else if(sclk_nege == 1'b1)begin
        mosi <= spi_data[23];
        spi_data <= {spi_data[22:0],1'b0};
    end
    else begin
        mosi <= mosi;
        spi_data <= spi_data;
    end
end

assign AD_cs_n = cs_reg ;
assign AD_sclk = sclk_reg ;
assign AD_mosi = mosi ;

// dco上升沿获取ADC数据
always@( posedge dco or negedge rst_n )
begin
    if(!rst_n)
        data_out <= 12'd0;
    else
        data_out <= data_in;
end

endmodule
