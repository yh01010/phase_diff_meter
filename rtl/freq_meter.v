module  freq_meter
(
    input   wire            sys_clk         ,   //系统时钟,50MHz
    input   wire            sys_rst_n       ,   //复位信号
    input   wire            clk_test        ,   //待检测时钟
    input   wire            clk_stand       ,   //标准时钟,100MHz
    
    output  reg     [31:0]  cnt_stand_reg   ,   //闸门内标准时钟周期数
    output  reg     [31:0]  cnt_test_reg    ,   //闸门内待检测时钟周期数
    output  reg             measure_done        //测量完成标志 
);

parameter   CNT_GATE_S_MAX  =   28'd74_999_999  ,   //软件闸门计数器计数最大值
            CNT_RISE_MAX    =   28'd12_500_000  ;   //软件闸门拉高计数值
parameter   CLK_STAND_FREQ  =   28'd100_000_000 ;   //标准时钟时钟频率

wire            gate_a_fall_s       ;   //实际闸门下降沿(标准时钟下)
wire            gate_a_fall_t       ;   //实际闸门下降沿(待检测时钟下)
reg     [27:0]  cnt_gate_s          ;   //软件闸门计数器
reg             gate_s              ;   //软件闸门
reg             gate_a              ;   //实际闸门
reg             gate_a_stand        ;   //实际闸门打一拍(标准时钟下)
reg             gate_a_test         ;   //实际闸门打一拍(待检测时钟下)
reg     [31:0]  cnt_clk_stand       ;   //标准时钟周期计数器
reg     [31:0]  cnt_clk_test        ;   //待检测时钟周期计数器
reg             gate_a_fall_s_sync1 ;   //标准时钟下闸门下降沿同步到sys_clk第一拍
reg             gate_a_fall_s_sync2 ;   //标准时钟下闸门下降沿同步到sys_clk第二拍
wire            gate_a_fall_s_sys   ;   //同步到sys_clk域的闸门下降沿


//软件闸门计数器
always@(posedge sys_clk,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_gate_s  <=  28'd0;
    else if(cnt_gate_s == CNT_GATE_S_MAX)
        cnt_gate_s  <=  28'd0;
    else
        cnt_gate_s  <=  cnt_gate_s + 1'b1;

//软件闸门
always@(posedge sys_clk,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gate_s  <=  1'b0;
    else if((cnt_gate_s>= CNT_RISE_MAX) && (cnt_gate_s <= (CNT_GATE_S_MAX - CNT_RISE_MAX)))
        gate_s  <=  1'b1;
    else
        gate_s  <=  1'b0;

//实际闸门
always@(posedge clk_test,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gate_a  <=  1'b0;
    else
        gate_a  <=  gate_s;

//标准时钟周期计数器,计数实际闸门下标准时钟周期数
always@(posedge clk_stand,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_clk_stand   <=  32'd0;  //原代码此处为48'd0，修正为32位避免位宽不匹配
    else if(gate_a == 1'b0)
        cnt_clk_stand   <=  32'd0;
    else if(gate_a == 1'b1)
        cnt_clk_stand   <=  cnt_clk_stand + 1'b1;

//待检测时钟周期计数器,计数实际闸门下待检测时钟周期数
always@(posedge clk_test,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_clk_test    <=  32'd0;  //原代码此处为48'd0，修正为32位避免位宽不匹配
    else if(gate_a == 1'b0)
        cnt_clk_test    <=  32'd0;
    else if(gate_a == 1'b1)
        cnt_clk_test    <=  cnt_clk_test + 1'b1;

//实际闸门打一拍(标准时钟下)
always@(posedge clk_stand,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gate_a_stand <= 1'b0;
    else
        gate_a_stand <= gate_a;

//实际闸门下降沿(标准时钟下)
assign  gate_a_fall_s = ((gate_a_stand == 1'b1) && (gate_a == 1'b0))
                        ? 1'b1 : 1'b0;

//实际闸门下标志时钟周期数
always@(posedge clk_stand,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_stand_reg   <=  32'd0;
    else if(gate_a_fall_s == 1'b1)
        cnt_stand_reg   <=  cnt_clk_stand;

//实际闸门打一拍(待检测时钟下)
always@(posedge clk_test,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gate_a_test <=  1'b0;
    else
        gate_a_test <=  gate_a;

//实际闸门下降沿(待检测时钟下)
assign  gate_a_fall_t = ((gate_a_test == 1'b1) && (gate_a == 1'b0)) ? 1'b1 : 1'b0;

//实际闸门下待检测时钟周期数
always@(posedge clk_test,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        cnt_test_reg   <=  32'd0;
    else if(gate_a_fall_t == 1'b1)
        cnt_test_reg   <=  cnt_clk_test;

//将标准时钟下的闸门下降沿同步到sys_clk域
always@(posedge sys_clk,negedge sys_rst_n)
    if(sys_rst_n == 1'b0) begin
        gate_a_fall_s_sync1 <= 1'b0;
        gate_a_fall_s_sync2 <= 1'b0;
    end 
    else begin
        gate_a_fall_s_sync1 <= gate_a_fall_s;
        gate_a_fall_s_sync2 <= gate_a_fall_s_sync1;
    end

//同步后的闸门下降沿（单周期脉冲）
assign gate_a_fall_s_sys = gate_a_fall_s_sync1 & (~gate_a_fall_s_sync2);


//测量完成标志：闸门下降沿时置位，持续一个sys_clk周期
always@(posedge sys_clk,negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        measure_done <= 1'b0;
    else if(gate_a_fall_s_sys == 1'b1)  //闸门关闭，一次测量完成
        measure_done <= 1'b1;
    else
        measure_done <= 1'b0;

endmodule
