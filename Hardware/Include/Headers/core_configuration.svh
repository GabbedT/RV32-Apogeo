`ifndef CONFIGURATION_INCLUDE_SV
    `define CONFIGURATION_INCLUDE_SV

//--------------------//
//  SYNTHESIS CONFIG  //
//--------------------//

    /* Target ASIC synthesis:
     *
     * - Clock gating
     * - Latch based register file */
    // `define ASIC
    
    /* Target FPGA synthesis:
     * 
     * - Clock enable 
     * - BRAM based register file */
    `define FPGA
    
    /* Enable asyncronous reset */
    `define ASYNC


//---------------//
//  CORE CONFIG  //
//---------------//

    /* Enable floating point unit and F extension */
    `define FLOATING_POINT_UNIT 

    /* Enable or disable cache */
    `define CACHE_SYSTEM


//----------------------//
//  MULTIPLIERS CONFIG  //
//----------------------//

    /* If "ASIC" is defined then the multiplier will automatically be generated 
     * with the appropriate number of pipeline stages.
     * 
     * If "FPGA" is defined then first the multiplier must be generated by the 
     * vendor tool, then the define with the stages number must be set based on
     * the IP pipeline configuration.
     * 
     * If the use of a generated IP is not possible then the files "floating_point
     * _multiplier.sv" and "multiplication_unit.sv" must be modified with the 
     * right module */

    /* Number of pipeline stages in the core integer multiplier, so 
     * if (MUL_PIPE_STAGES == 0) the multiplier will be combinational */
    `define MUL_PIPE_STAGES 2

    /* Number of pipeline stages in the core floating point multiplier,
     * so if (MUL_PIPE_STAGES == 0) the multiplier will be combinational */ 
    `define SIGNIFICAND_MUL_PIPE_STAGES 0


//--------------// 
//  DATA CACHE  //
//--------------//

    /* In bytes */
    `define DATA_CACHE_SIZE 2 ** 16

    /* In bits */
    `define DATA_CACHE_BLOCK_SIZE 128 

    /* Number of cache ways */
    `define DATA_CACHE_ASSOCIATIVITY 2

    /* Total number of entries in the store buffer (A power of 2) */
    `define ST_BUF_DEPTH 4


//---------------------//
//  EXCEPTIONS VECTOR  //
//---------------------//

    `define DIVIDE_BY_ZERO        4'b0000;
    `define ILLEGAL_MEMORY_ACCESS 4'b0001;

`endif 