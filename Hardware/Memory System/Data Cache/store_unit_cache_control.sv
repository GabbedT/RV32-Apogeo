`ifndef STORE_UNIT_CACHE_CONTROL_SV
    `define STORE_UNIT_CACHE_CONTROL_SV

`include "../../Include/data_memory_pkg.sv"

module store_unit_cache_control (
    input  logic                    clk_i,
    input  logic                    rst_n_i,

    /* External interface */
    input  logic                    external_invalidate_i,
    input  data_cache_addr_t        external_invalidate_address_i,
    output logic                    processor_acknowledge_o,

    /* Store unit interface */
    input  logic                    store_unit_write_cache_i,
    input  logic [PORT_WIDTH - 1:0] store_unit_data_i,
    input  data_cache_addr_t        store_unit_full_address_i,
    input  mem_op_width_t           store_unit_data_width_i,

    /* Cache interface */
    input  logic                    cache_port0_idle_i,
    input  logic                    cache_hit_i,
    output logic                    cache_write_o,
    output logic                    cache_read_o,
    output data_cache_addr_t        cache_address_o,
    output logic [PORT_BYTES - 1:0] cache_byte_write_o, 
    output logic [PORT_WIDTH - 1:0] cache_data_o,
    output logic                    cache_dirty_o,
    output logic                    cache_valid_o,
    output data_cache_enable_t      cache_enable_o,

    output mem_op_width_t           data_width_o,
    input  logic                    store_buffer_idle_i,
    output logic                    push_store_buffer_o,
    output logic                    done_o,
    output logic                    idle_o
);


//-------------//
//  FSM LOGIC  //
//-------------//

    typedef enum logic [2:0] {IDLE, COMPARE_TAG, WRITE_DATA, MEMORY_WRITE, INVALIDATE} store_unit_cache_fsm_t;

    store_unit_cache_fsm_t state_CRT, state_NXT;

        always_ff @(posedge clk_i `ifdef ASYNC or negedge rst_n_i `endif) begin : state_register
            if (!rst_n_i) begin
                state_CRT <= IDLE;
            end else begin
                state_CRT <= state_NXT;
            end
        end : state_register

    assign idle_o = (state_NXT == IDLE);


        always_comb begin : fsm_logic
            /* Default values */
            state_NXT = state_CRT;

            done_o = 1'b0;
            push_store_buffer_o = 1'b0;
            processor_acknowledge_o = 1'b0;
            data_width_o = BYTE;
            
            cache_read_o = 1'b0;
            cache_write_o = 1'b0;
            cache_enable_o = 4'b0;
            cache_dirty_o = 1'b0;
            cache_valid_o = 1'b0;
            cache_address_o = 'b0;
            cache_byte_write_o = 'b0;
            cache_data_o = 'b0;

            case (state_CRT)

                /* 
                 *  Stay idle until a valid address is received, 
                 *  send address to cache and read immediately 
                 */
                IDLE: begin
                    /* Store request and invalidate request need to read the
                     * cache block first */
                    if (external_invalidate_i & cache_port0_idle_i) begin
                        state_NXT = COMPARE_TAG;

                        /* Initiate cache read */
                        cache_read_o = 1'b1;
                        cache_address_o = external_invalidate_address_i;

                        cache_enable_o = 4'b1;
                        processor_acknowledge_o = 1'b1;

                    end else if (store_unit_write_cache_i & cache_port0_idle_i) begin
                        state_NXT = COMPARE_TAG;

                        /* Initiate cache read */
                        cache_read_o = 1'b1;
                        cache_address_o = store_unit_full_address_i;

                        cache_enable_o = 4'b1;
                    end 
                end

                /* 
                 *  The block is retrieved from cache, the tag is then compared
                 *  to part of the address sended and an hit signal is received.
                 */
                COMPARE_TAG: begin
                    if (external_invalidate_i) begin
                        cache_address_o = external_invalidate_address_i;

                        if (cache_hit_i) begin
                            state_NXT = INVALIDATE;
                        end else begin
                            /* If a miss happens the invalid block 
                             * is not in cache, no further operations
                             * are needed */
                            state_NXT = IDLE;
                        end  
                    end else if (store_unit_write_cache_i) begin 
                        cache_address_o = store_unit_full_address_i;

                        if (cache_hit_i) begin
                            /* Write in cache */
                            state_NXT = WRITE_DATA;
                        end else begin
                            /* Send a write request to memory
                             * unit */
                            state_NXT = MEMORY_WRITE;
                        end
                    end 
                end

                /* 
                 *  Simply write data into cache, tag it as dirty. Write data
                 *  memory block and dirty memory block.
                 */
                WRITE_DATA: begin
                    cache_write_o = 1'b1;
                    cache_address_o = store_unit_full_address_i;
                    
                    cache_dirty_o = 1'b1;

                    cache_enable_o.data = 1'b1;
                    cache_enable_o.dirty = 1'b1;

                    state_NXT = IDLE;
                    done_o = 1'b1;

                    case (store_unit_data_width_i)
                        BYTE: begin 
                            cache_byte_write_o[store_unit_full_address_i.byte_sel] = 1'b1;

                            case (store_unit_full_address_i.byte_sel) 
                                2'b00: cache_data_o[7:0] = store_unit_data_i[7:0];

                                2'b01: cache_data_o[15:8] = store_unit_data_i[7:0];

                                2'b10: cache_data_o[23:16] = store_unit_data_i[7:0];

                                2'b11: cache_data_o[31:24] = store_unit_data_i[7:0];
                            endcase
                        end 

                        HALF_WORD: begin
                            if (store_unit_full_address_i.byte_sel[1]) begin
                                /* Write upper 16 bits */
                                cache_byte_write_o = 4'b1100;
                                cache_data_o[PORT_WIDTH - 1:(PORT_WIDTH / 2)] = store_unit_data_i[(PORT_WIDTH / 2) - 1:0];
                            end else begin
                                /* Write lower 16 bits */
                                cache_byte_write_o = 4'b0011;
                                cache_data_o[(PORT_WIDTH / 2) - 1:0] = store_unit_data_i;
                            end
                        end

                        WORD, DOUBLE_WORD: begin
                            /* Write word */
                            cache_byte_write_o = 4'b1111;
                            cache_data_o = store_unit_data_i;
                        end
                    endcase
                end

                /*
                 *  Write data into the write buffer 
                 */
                MEMORY_WRITE: begin
                    push_store_buffer_o = store_buffer_idle_i;

                    data_width_o = store_unit_data_width_i;
                    cache_address_o = store_unit_full_address_i;
                    cache_data_o = store_unit_data_i;

                    done_o = 1'b1;
                    state_NXT = IDLE;
                end

                /* 
                 *  Invalidate cache entry by writing valid bit
                 */
                INVALIDATE: begin
                    cache_address_o = store_unit_full_address_i;
                    cache_enable_o.valid = 1'b1;
                    cache_valid_o = 1'b0;
                    
                    done_o = 1'b1;
                    state_NXT = IDLE;
                end
            endcase
        end : fsm_logic

endmodule : store_unit_cache_control

`endif 