module AD9226 
(
    input   wire            clk         ,  //系统时钟
    input   wire            rst_n       ,  //复位信号
    input   wire    [11:0]  data_in_A   ,  //通道A数据输入
    input   wire    [11:0]  data_in_B   ,  //通道B数据输入
                                                  
    output  wire            clk_A       ,  //输出到A通道的时钟
    output  wire            clk_B       ,  //输出到B通道的时钟
    output  reg     [11:0]  data_out_A  ,  //通道A处理后数据输出
    output  reg     [11:0]  data_out_B     //通道B处理后数据输出
);

parameter PIPELINE_DELAY = 7    ;  //流水线延迟：7个时钟周期
parameter CALIB_CYCLES   = 100  ;  //复位校准周期：100个时钟（覆盖初始化时间）

assign clk_A = clk;
assign clk_B = clk;

reg [11:0] data_in_A_rev;  //通道A位序反转后数据
reg [11:0] data_in_B_rev;  //通道B位序反转后数据

//流水线延迟寄存器
reg [11:0] pipe_A [PIPELINE_DELAY-1:0];
reg [11:0] pipe_B [PIPELINE_DELAY-1:0];

//校准计数器与完成标志
reg [$clog2(CALIB_CYCLES)-1:0] calib_cnt;
reg                            calib_done;

//位序反转：
always @(*) begin
    integer i;
    for(i=0; i<12; i=i+1) begin
        data_in_A_rev[i] = data_in_A[11 - i];
        data_in_B_rev[i] = data_in_B[11 - i];
    end
end

//复位校准计数器：确保芯片初始化完成后再输出有效数据
always @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
        calib_cnt  <= 'd0;
        calib_done <= 1'b0;
    end
    else if(!calib_done) begin
        if(calib_cnt >= CALIB_CYCLES - 1'b1) begin
            calib_cnt  <= calib_cnt;
            calib_done <= 1'b1;
        end
        else begin
            calib_cnt <= calib_cnt + 1'b1;
        end
    end
end


integer j;
//流水线延迟：匹配AD9226的7个时钟周期输出延迟
always @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
        for(j=0; j<PIPELINE_DELAY; j=j+1) begin
            pipe_A[j] <= 'd0;
            pipe_B[j] <= 'd0;
        end
    end
    else begin
        // 输入级：位序修正后的数据进入流水线
        pipe_A[0] <= data_in_A_rev;
        pipe_B[0] <= data_in_B_rev;   
        // 流水线级联
        for(j=1; j<PIPELINE_DELAY; j=j+1) begin
            pipe_A[j] <= pipe_A[j-1];
            pipe_B[j] <= pipe_B[j-1];
        end
    end
end

//数据输出：校准完成后输出延迟处理后的数据
always @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
        data_out_A <= 'd0;
        data_out_B <= 'd0;
    end
    else if(calib_done) begin
        data_out_A <= 'd4095 - pipe_A[PIPELINE_DELAY-1];
        data_out_B <= 'd4095 - pipe_B[PIPELINE_DELAY-1];
    end
    else begin
        data_out_A <= 'd0;
        data_out_B <= 'd0;
    end
end

endmodule
