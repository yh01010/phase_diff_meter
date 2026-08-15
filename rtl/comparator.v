module comparator  //比较器模块
#(
    parameter   LIMIT =  'd2048  //比较阈值
)
(
    input   wire            clk     ,  //系统时钟
    input   wire            rst_n   ,  //复位信号
    input   wire    [11:0]  data_in ,  //数据输入
    
    output  reg             result     //比较结果
);

always @(posedge clk,negedge rst_n) begin
    if(!rst_n)
        result <= 1'b0;
    else if(data_in >= LIMIT)
        result <= 1'b1;  //输入≥阈值,输出高
    else
        result <= 1'b0;  //输入<阈值,输出低
end

endmodule
