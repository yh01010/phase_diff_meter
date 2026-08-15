module phase_meter
(
    input   wire            clk         ,  //时钟信号
    input   wire            rst_n       ,  //复位信号
    input   wire            signal_test ,  //待检测的信号
    
    output  reg     [31:0]  time_cnt_reg   //时间计数器
);

localparam CNT_MAX = 'd4_294_967_295;  //计数器最大值

reg signal_test_dly1;
reg signal_test_dly2;
wire signal_test_rise;
wire signal_test_fall;
reg [31:0]  time_cnt;

always @(posedge clk,negedge rst_n) begin
    if(!rst_n) begin
        signal_test_dly1 <= 'b0;
        signal_test_dly2 <= 'b0;
    end
    else begin
        signal_test_dly1 <= signal_test;
        signal_test_dly2 <= signal_test_dly1;
    end
end

assign signal_test_rise = signal_test_dly1 && (!signal_test_dly2);  //捕捉待测信号的上升沿
assign signal_test_fall = (!signal_test_dly1) && signal_test_dly2;  //捕捉待测信号的下降沿

always @(posedge clk,negedge rst_n) begin
    if(!rst_n) begin 
        time_cnt <= 'd0;
        time_cnt_reg <= 'd0;
    end
    else if(time_cnt == CNT_MAX)
        time_cnt <= 'd0;
    else if(signal_test_rise) begin
        time_cnt_reg <= time_cnt;
        time_cnt <= 'd0;
    end
    else
        time_cnt <= time_cnt + 'd1;
end

endmodule
