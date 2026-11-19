`timescale 1ns / 1ps

// Horner's Rule Serial Radix Converter
// Converts an MSB-first digit stream in base [2..16] into a 16-bit unsigned integer:
//   acc_next = acc * base + digit
module horner_radix_conv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        digit_valid,
    input  wire        last_digit,
    input  wire [3:0]  digit_in,
    input  wire [4:0]  base_in,
    output reg  [15:0] result_out,
    output reg         done,
    output reg         overflow,
    output reg         busy
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [1:0]  state;
    reg [15:0] acc;
    reg [4:0]  base_reg;
    reg        ovf_reg;

    // 16-bit * 5-bit = 21-bit intermediate product + 4-bit digit
    wire [20:0] mult_val = acc * base_reg;
    wire [20:0] next_val = mult_val + {17'd0, digit_in};
    wire        invalid_digit = ({1'b0, digit_in} >= base_reg);
    wire        step_ovf = (next_val[20:16] != 5'd0) || invalid_digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            acc        <= 16'd0;
            base_reg   <= 5'd10;
            ovf_reg    <= 1'b0;
            result_out <= 16'd0;
            done       <= 1'b0;
            overflow   <= 1'b0;
            busy       <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        acc      <= 16'd0;
                        // Clamp invalid base (<2 or >16) to base 10
                        base_reg <= (base_in >= 5'd2 && base_in <= 5'd16) ? base_in : 5'd10;
                        ovf_reg  <= 1'b0;
                        overflow <= 1'b0;
                        busy     <= 1'b1;
                        state    <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    busy <= 1'b1;
                    if (start) begin
                        // Allow restart mid-conversion
                        acc      <= 16'd0;
                        base_reg <= (base_in >= 5'd2 && base_in <= 5'd16) ? base_in : 5'd10;
                        ovf_reg  <= 1'b0;
                        overflow <= 1'b0;
                    end else if (digit_valid) begin
                        if (step_ovf) begin
                            ovf_reg <= 1'b1;
                        end else begin
                            acc <= next_val[15:0];
                        end

                        if (last_digit) begin
                            state <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    result_out <= ovf_reg ? 16'hFFFF : acc;
                    overflow   <= ovf_reg;
                    done       <= 1'b1;
                    busy       <= 1'b0;
                    state      <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
