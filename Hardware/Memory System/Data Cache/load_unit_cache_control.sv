`ifndef LOAD_UNIT_CACHE_CONTROL_SV
    `define LOAD_UNIT_CACHE_CONTROL_SV

`include "../../Include/data_memory_pkg.sv"
`include "../../Include/configuration_pkg.sv"

module load_unit_cache_control (
    input  logic                     clk_i,
    input  logic                     rst_n_i,

    /* External interface */
    input  logic [PORT_WIDTH - 1:0]  external_data_i,
    input  logic                     external_data_valid_i,
    input  logic                     cache_line_valid_i,
    input  logic                     external_acknowledge_i,
    output logic                     processor_request_o,

    /* Store unit interface */
    input  logic                     wr_buffer_address_match_i,
    input  logic [PORT_WIDTH - 1:0]  wr_buffer_data_i,
    input  logic [PORT_WIDTH - 1:0]  store_unit_data_i,
    input  logic [31:0]              store_unit_address_i,
    input  logic                     store_unit_idle_i,

    /* Load unit interface */
    input  logic                     load_unit_read_cache_i,
    input  data_cache_addr_t         load_unit_address_i,

    /* Cache interface */
    input  logic                     cache_port0_idle_i,
    input  logic                     cache_port1_hit_i,
    input  logic                     cache_dirty_i,
    input  logic [PORT_WIDTH - 1:0]  cache_data_i,
    output logic                     cache_dirty_o,
    output logic                     cache_valid_o,
    output logic                     cache_port1_read_o, 
    output logic                     cache_port0_write_o,
    output logic [WAYS_NUMBER - 1:0] cache_enable_way_o,
    output data_cache_addr_t         cache_address_o,
    output data_cache_enable_t       cache_enable_o,

    input  logic                     store_buffer_full_i,
    input  logic                     store_buffer_port_idle_i,
    output logic [PORT_WIDTH - 1:0]  data_o,
    output mem_op_width_t            data_width_o,
    output logic                     data_valid_o,
    output logic                     push_store_buffer_o,
    output logic                     done_o,
    output logic                     idle_o
);


//------------//
//  DATAPATH  //
//------------//

    /* Store cache line from external memory */
    logic [BLOCK_WIDTH - 1:0] external_memory_data;

        always_ff @(posedge clk_i) begin : memory_data_register
            if (external_data_valid_i) begin 
                external_memory_data <= {external_data_i, external_memory_data[BLOCK_WIDTH - 1:PORT_WIDTH]};
            end
        end : memory_data_register


    /* Store data from cache */
    logic [PORT_WIDTH - 1:0] cache_data_CRT, cache_data_NXT;

        always_ff @(posedge clk_i) begin : cache_data_register
            cache_data_CRT <= cache_data_NXT;
        end : cache_data_register

    
    /* Memory data cache interface is 32 bit wide, while cache line is wider than that, count the number of
     * word writes while allocating the line */
    logic [CHIP_ADDR - 1:0] chip_select_CRT, chip_select_NXT;

        always_ff @(posedge clk_i `ifdef ASYNC or negedge rst_n_i `endif) begin : chip_select_register
            if (!rst_n_i) begin
                chip_select_CRT <= 'b0;
            end else begin
                chip_select_CRT <= chip_select_NXT;
            end
        end : chip_select_register


    /* LFSR for selecting the way to replace with random policy */
    logic [2:0] lfsr_data;
    logic       lfsr_function, enable_lfsr;
    logic [1:0] random_way;

    assign lfsr_function = !(lfsr_data[2] ^ lfsr_data[1]);

        always_ff @(posedge clk_i `ifdef ASYNC or negedge rst_n_i `endif) begin : lfsr_shift_register
            if (!rst_n_i) begin
                lfsr_data <= 3'b010;
            end else if (enable_lfsr) begin
                lfsr_data <= {lfsr_data[1:0], lfsr_function};
            end
        end : lfsr_shift_register

    assign random_way = lfsr_data[1:0];

    assign cache_enable_way_o = random_way;


    /* Check if store unit is writing in the same memory location */
    logic store_unit_address_match;

    assign store_unit_address_match = (store_unit_address_i == load_unit_address_i) & !store_unit_idle_i;


//-------------//
//  FSM LOGIC  //
//-------------//

    typedef enum logic [2:0] {IDLE, COMPARE_TAG, DATA_STABLE, MEMORY_REQUEST, DIRTY_CHECK, READ_CACHE, WRITE_BACK, ALLOCATE} load_unit_cache_fsm_t;

    load_unit_cache_fsm_t state_CRT, state_NXT;

        always_ff @(posedge clk_i `ifdef ASYNC or negedge rst_n_i `endif) begin : state_register
            if (!rst_n_i) begin
                state_CRT <= IDLE;
            end else begin
                state_CRT <= state_NXT;
            end
        end : state_register


        always_comb begin : fsm_logic
            case (state_CRT)

                /* 
                 *  Stay idle until a valid address is received, 
                 *  send address to cache and read immediately 
                 *  the data, tag and status.
                 */
                IDLE: begin
                    if (load_unit_read_cache_i) begin
                        state_NXT = COMPARE_TAG;

                        /* Access all the cache */
                        cache_enable_o = 4'b1;

                        /* Cache control */
                        cache_port1_read_o = 1'b1;
                        cache_address_o.index = load_unit_full_address_i.index;
                        cache_address_o.chip_sel = load_unit_full_address_i.chip_sel;

                        /* If data is found in the store buffer or is inside the 
                         * store unit, there's no need to check for an hit */
                        if (store_unit_address_match) begin 
                            state_NXT = DATA_STABLE;
                            cache_data_NXT = store_unit_data_i;
                        end else if (wr_buffer_address_match_i) begin
                            state_NXT = DATA_STABLE;
                            cache_data_NXT = wr_buffer_data_i;                            
                        end
                    end
                end


                /* 
                 *  The block is retrieved from cache, the tag is then compared
                 *  to part of the address sended and an hit signal is received
                 */
                COMPARE_TAG: begin
                    if (cache_port1_hit_i) begin
                        state_NXT = DATA_STABLE; 
                        cache_data_NXT = cache_packet_i.word; 
                    end else begin
                        state_NXT = MEMORY_REQUEST;
                    end
                end


                /*
                 *  Data is ready to be used 
                 */
                DATA_STABLE: begin
                    data_valid_o = 1'b1;
                    state_NXT = IDLE;
                end


                /*
                 *  Send a read request to memory unit and read the cache dirty 
                 *  bit at the same time. Only the dirty bit needs to be accessed.
                 */
                MEMORY_REQUEST: begin
                    processor_request_o = 1'b1;

                    if (external_acknowledge_i) begin
                        state_NXT = READ_CACHE;

                        cache_port1_read_o = 1'b1;
                        cache_address_o = load_unit_address_i; 

                        enable_lfsr = 1'b0;

                        cache_enable_o.dirty = 1'b1;
                    end
                end


                /*
                 *  Check if the block is dirty. if dirty then the block needs to
                 *  be written back to memory. Else just allocate new data.
                 */
                DIRTY_CHECK: begin
                    chip_select_NXT = 'b0;
                    enable_lfsr = 1'b0;

                    if (cache_dirty_i) begin
                        state_NXT = WRITE_BACK;
                    end else begin
                        state_NXT = ALLOCATE;
                    end
                end


                /*
                 *  Send address and control signal to cache to read a word. Start 
                 *  from the first word of the block and then increment until the
                 *  last one.
                 */
                READ_CACHE: begin
                    cache_address_o = {load_unit_address_i.tag, load_unit_address_i.index, chip_select_CRT};

                    cache_port1_read_o = 1'b1;
                    chip_select_NXT = chip_select_CRT + 1'b1;
                    cache_enable_o.word = 1'b1;  

                    enable_lfsr = 1'b0;
                    state_NXT = WRITE_BACK;
                end

                
                /*
                 *  Write data, address and data width to store buffer 
                 */
                WRITE_BACK: begin
                    enable_lfsr = 1'b0;

                    if (!store_buffer_full_i & store_buffer_port_idle_i) begin
                        data_width_o = WORD;
                        data_o = cache_data_i;
                        cache_address_o = load_unit_address_i;

                        push_store_buffer_o = 1'b1;

                        /* If the end of the block is reached, allocate a new block */
                        if (chip_select_CRT == (BLOCK_WIDTH / PORT_WIDTH - 1)) begin
                            state_NXT = ALLOCATE;
                            chip_select_NXT = 'b0;
                        end else begin
                            state_NXT = READ_CACHE;
                        end
                    end
                end


                /*
                 *  When the entire cache line has been received from the memory,
                 *  write multiple times the cache keeping the index and incrementing
                 *  the chip select signal as the write happens. In the first write
                 *  allocate status and tag bits.
                 */
                ALLOCATE: begin
                    if (cache_line_valid_i & cache_port0_idle_i) begin
                        if (chip_select_CRT == 'b0) begin
                            cache_enable_o = 4'b1;

                            cache_dirty_o = 1'b0;
                            cache_valid_o = 1'b1;
                        end else begin
                            cache_enable_o.data = 1'b1;
                        end

                        cache_port0_write_o = 1'b1;
                        data_o = external_memory_data[PORT_WIDTH - 1:0];

                        external_memory_data = external_memory_data >> PORT_WIDTH;

                        /* End of cache line reached */
                        if (chip_select_CRT == (BLOCK_WIDTH / PORT_WIDTH - 1)) begin
                            state_NXT = IDLE;
                            done_o = 1'b1;
                        end
                    end
                end
            endcase
        end : fsm_logic

    assign idle_o = (state_NXT == IDLE);

endmodule : load_unit_cache_control

`endif 