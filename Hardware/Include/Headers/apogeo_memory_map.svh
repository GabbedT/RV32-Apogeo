`ifndef CORE_MEMORY_MAP_SV
    `define CORE_MEMORY_MAP_SV

    `define KILO(bytes) (bytes * (2 ** 10)) - 1
    `define MEGA(bytes) (bytes * (2 ** 20)) - 1
    `define GIGA(bytes) (bytes * (2 ** 30)) - 1

    /* 
     *  Boot memory region 
     *
     *  NON CACHABLE
     *  NON WRITABLE
     *  NON BUFFERABLE
     */
    `define BOOT_START 32'h0000_0000
    `define BOOT_END   `BOOT_START + `KILO(2)


    /* 
     *  Input / Output memory region 
     *
     *  NON CACHABLE
     *  NON BUFFERABLE
     */
    `define IO_START `BOOT_END + 1'b1
    `define IO_END   `IO_START + `KILO(128)


    /* 
     *  General purpouse memory region 
     */
    `define CODE_START `IO_END + 1
    `define CODE_END   32'hFFFF_FFFF

`endif 