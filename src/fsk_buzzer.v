// Tang Nano 1K: Kansas City Standard (KCS) FSK buzzer
//
// 27 MHz clock, 300 baud
//   mark  (logic 1): 2400 Hz, 8 cycles per bit
//   space (logic 0): 1200 Hz, 4 cycles per bit
// Frame: start(0), 8-bit LSB-first data, stop(1), stop(1)
//
// Connect a passive piezo / electromagnetic buzzer through a suitable
// transistor driver. Do not drive a large buzzer directly from an FPGA pin.

module fsk_buzzer (
    input  wire clk_27m,
    input  wire key_a_n,
    input  wire key_b_n,
    output wire buzzer,
    output wire led_g_n
);

    localparam [31:0] PHASE_1200 = 32'd190887; // 1200 * 2^32 / 27 MHz
    localparam [31:0] PHASE_2400 = 32'd381775; // 2400 * 2^32 / 27 MHz
    localparam [16:0] BAUD_TICKS = 17'd89999; // 27 MHz / 300 - 1
    localparam [26:0] LEVEL_TICKS = 27'd107999999; // 4 s at 27 MHz

    reg [31:0] phase;
    reg [16:0] baud_count;
    reg [3:0]  bit_count;
    reg [4:0]  message_index;
    reg [3:0]  startup;
    reg [7:0]  current_byte;
    reg        tx_bit;
    reg        buzzer_q;
    reg        running;
    reg        level_tone;
    reg [26:0] level_count;
    reg        key_a_meta;
    reg        key_a_sync;
    reg        key_b_meta;
    reg        key_b_sync;
    reg [15:0] key_a_filter;
    reg [15:0] key_b_filter;
    reg        key_a_pressed;
    reg        key_b_pressed;
    reg        key_a_pressed_d;
    reg        key_b_pressed_d;

    // Gowin FPGA flip-flops support power-up initialization. This also makes
    // RTL simulation start from the same state as the programmed device.
    initial begin
        phase         = 32'd0;
        baud_count    = 17'd0;
        bit_count     = 4'd0;
        message_index = 5'd0;
        startup       = 4'd0;
        buzzer_q      = 1'b0;
        running       = 1'b0;
        level_tone    = 1'b0;
        level_count   = 27'd0;
        key_a_meta    = 1'b1;
        key_a_sync    = 1'b1;
        key_b_meta    = 1'b1;
        key_b_sync    = 1'b1;
        key_a_filter  = 16'd0;
        key_b_filter  = 16'd0;
        key_a_pressed = 1'b0;
        key_b_pressed = 1'b0;
        key_a_pressed_d = 1'b0;
        key_b_pressed_d = 1'b0;
    end

    // Synchronize and debounce the active-low push buttons.
    // The 16-bit integrator corresponds to about 2.4 ms at 27 MHz.
    always @(posedge clk_27m) begin
        key_a_meta <= key_a_n;
        key_a_sync <= key_a_meta;
        key_b_meta <= key_b_n;
        key_b_sync <= key_b_meta;

        if (!key_a_sync) begin
            if (key_a_filter != 16'hffff)
                key_a_filter <= key_a_filter + 1'b1;
            else
                key_a_pressed <= 1'b1;
        end else begin
            if (key_a_filter != 16'd0)
                key_a_filter <= key_a_filter - 1'b1;
            else
                key_a_pressed <= 1'b0;
        end

        if (!key_b_sync) begin
            if (key_b_filter != 16'hffff)
                key_b_filter <= key_b_filter + 1'b1;
            else
                key_b_pressed <= 1'b1;
        end else begin
            if (key_b_filter != 16'd0)
                key_b_filter <= key_b_filter - 1'b1;
            else
                key_b_pressed <= 1'b0;
        end

        key_a_pressed_d <= key_a_pressed;
        key_b_pressed_d <= key_b_pressed;
    end

    // Send the alphabet A-Z, repeated forever.
    always @* begin
        if (message_index < 5'd26)
            current_byte = 8'h41 + message_index;
        else
            current_byte = 8'h41;
    end

    // KCS bit stream: start(0), LSB first data, two stop(1) bits.
    always @* begin
        case (bit_count)
            4'd0:    tx_bit = 1'b0;
            4'd1:    tx_bit = current_byte[0];
            4'd2:    tx_bit = current_byte[1];
            4'd3:    tx_bit = current_byte[2];
            4'd4:    tx_bit = current_byte[3];
            4'd5:    tx_bit = current_byte[4];
            4'd6:    tx_bit = current_byte[5];
            4'd7:    tx_bit = current_byte[6];
            4'd8:    tx_bit = current_byte[7];
            4'd9:    tx_bit = 1'b1;
            default: tx_bit = 1'b1;
        endcase
    end

    // A few startup clocks give the FPGA fabric deterministic initial state.
    // The design starts stopped; A starts from the first frame and B stops it.
    always @(posedge clk_27m) begin
        if (startup != 4'hf) begin
            startup       <= startup + 1'b1;
            phase         <= 32'd0;
            baud_count    <= 17'd0;
            bit_count     <= 4'd0;
            message_index <= 5'd0;
            buzzer_q      <= 1'b0;
            running       <= 1'b0;
            level_tone    <= 1'b0;
            level_count   <= 27'd0;
        end else begin
            if (key_b_pressed) begin
                running    <= 1'b0;
                level_tone <= 1'b0;
                level_count <= 27'd0;
                phase      <= 32'd0;
                buzzer_q   <= 1'b0;
            end else if (key_a_pressed && !key_a_pressed_d) begin
                running       <= 1'b1;
                level_tone    <= 1'b1;
                level_count   <= 27'd0;
                phase         <= 32'd0;
                baud_count    <= 17'd0;
                bit_count     <= 4'd0;
                message_index <= 5'd0;
                buzzer_q      <= 1'b0;
            end else if (running) begin
                if (level_tone) begin
                    // Four-second 1200 Hz reference tone for level setting.
                    phase <= phase + PHASE_1200;
                    buzzer_q <= phase[31];
                    if (level_count == LEVEL_TICKS) begin
                        level_tone    <= 1'b0;
                        level_count   <= 27'd0;
                        phase         <= 32'd0;
                        baud_count    <= 17'd0;
                        bit_count     <= 4'd0;
                        message_index <= 5'd0;
                    end else begin
                        level_count <= level_count + 1'b1;
                    end
                end else begin
                    phase <= phase + (tx_bit ? PHASE_2400 : PHASE_1200);
                    buzzer_q <= phase[31];

                    if (baud_count == BAUD_TICKS) begin
                        baud_count <= 17'd0;
                        if (bit_count == 4'd10) begin
                            bit_count <= 4'd0;
                            if (message_index == 5'd25)
                                message_index <= 5'd0;
                            else
                                message_index <= message_index + 1'b1;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end
            end else begin
                buzzer_q <= 1'b0;
            end
        end
    end

    assign buzzer = buzzer_q;
    // The onboard RGB LED is active-low. Show the current serial bit while
    // transmitting: mark/1 turns the green LED on, space/0 turns it off.
    // Keep it on during the level-setting reference tone.
    assign led_g_n = !(running && (level_tone || tx_bit));

endmodule
