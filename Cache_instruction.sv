module cache_instruction
( Clock, reset, command, tr_addr , instruction_read, instruction_write, 
  instruction_hit, instruction_miss, mode, s);

  input logic Clock;
  input logic reset;
  input logic mode;
  input bit s;
  input logic [3:0]  command;       								// from trace file
  input logic [31:0] tr_addr;	  								// Address from trace file

  output real instruction_read, instruction_write, instruction_hit, instruction_miss;

  typedef enum {Modif, Exclus, Shared, Invalid} STATE;                                        //Declaring states

  parameter CACHE_LINE_SIZE = 64; 									// Width of cache line in bytes
  parameter BYTE_OFFSET_BITS = $clog2 (CACHE_LINE_SIZE);						// Number of byte offset bits
  parameter ADDRESS_BITS = 32;										// Number of Address Bits
  parameter SETS = 16*1024;									// Total number of SETS
  parameter WAYS = 4;										// Total number of WAYS
  parameter SET_SELECT_BITS = $clog2 (SETS);							// Number of byte offset bits
  parameter TAG_BITS = ADDRESS_BITS - (BYTE_OFFSET_BITS + SET_SELECT_BITS);				// Number of TAG bits
  parameter LRU_BITS = $clog2 (WAYS);								// Number of LRU bits

  real instruction_hit_ratio; 									

  logic [LRU_BITS-1:0] LRU[SETS-1:0][WAYS-1:0] = {default:2'b00};				// LRU bits per cache line - Default set to 00
  logic [TAG_BITS-1:0] TAG[SETS-1:0][WAYS-1:0];						// TAG bits per cache line
  bit valid[SETS-1:0][WAYS-1:0];
  bit first_write_through [SETS -1: 0] [WAYS-1:0];

  STATE MESI[SETS-1 : 0][WAYS-1:0];

  int exit=0;
  int valid_bit_count = 0;

  logic [BYTE_OFFSET_BITS- 1 :0] byte_offset;
  logic [SET_SELECT_BITS-1 :0] set_index;
  logic [TAG_BITS -1 :0] tag_index;

  assign byte_offset = tr_addr [BYTE_OFFSET_BITS-1 :0];
  assign set_index = tr_addr [BYTE_OFFSET_BITS + SET_SELECT_BITS-1 :BYTE_OFFSET_BITS];
  assign tag_index = tr_addr [ADDRESS_BITS-1: BYTE_OFFSET_BITS + SET_SELECT_BITS];
 
  always@(s)
  begin
  display_cache_contents();
  display_report();
  end 
  
  always_ff @(posedge Clock, posedge reset)
    begin
      if(reset)
        begin
          instruction_read = 0;
          instruction_write = 0;
          instruction_hit = 0;
          instruction_miss = 0;
          foreach (MESI [x,y])
            begin
              TAG[x][y]=0;
              MESI[x][y] = Invalid;
              LRU[x][y] = 2'b00;
              first_write_through[x][y] = 0;
              valid[x][y] = 0;
            end
        end
      else
        begin if (command != 0 && command != 1 && command != 3 && command != 4)
            begin

              case(command)
                2:
                  begin
                    exit = 0;
                    for(int m=0 ; m<WAYS; m++)
                      begin if(valid[set_index][m] == 1)
                          valid_bit_count = valid_bit_count + 1;

                        ///////////////************************************ IF TAG BITS MATCH - HIT *********************************/////////////////////
                        if((exit==0 && valid[set_index][m] == 1) && ( TAG[set_index][m] == tag_index))
                          begin
                            exit = 1;
                            instruction_hit = instruction_hit+1;
                            $display("------TAG BITS MATCH, HENCE HIT-------");

                            //////////////////////////////--------------------MODIFIED STATE-----------------------///////////////////////////////////

                            if (MESI[set_index][m] == Modif)
                              begin
                                if (command == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modif;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
                              end

                            //////////////////////////////--------------------EXCLUSIVE STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Exclus)
                              begin
                                if (command == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
                              end

                            //////////////////////////////--------------------SHARED STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Shared)
                              begin
                                if (command == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
			      end 
                          end

                        ///////////////************************************ IF TAGS BITS DON'T MATCH - MISS *********************************/////////////////////


                        if((valid_bit_count < WAYS) && (exit == 0))
                          begin
                            instruction_miss = instruction_miss+1;
                            $display("------TAG BITS DONT MATCH, HENCE MISS-------");
                            for(int k=0; k<WAYS; k++)
                              begin if(exit==0 && LRU[set_index][k] == 0 && valid[set_index][k] == 0)
                                 begin
                                    exit = 1;

                                    if(command == 2)
                                      begin
                                        MESI[set_index][k] = Exclus;
                                        instruction_read = instruction_read+1;
                                        update_LRU(k);
                                        TAG[set_index][k] = tag_index;
                                        valid[set_index][k] = 1;
                                        if(mode == 1'b1)
                                          begin
                                            $display("--Communication with L2--");
                                            $display("Read from L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                      end
                                  end
                              end
                          end

                        if((valid_bit_count==WAYS) && (exit == 0))
                          begin
                            instruction_miss = instruction_miss+1;
                            $display("------TAG BITS DONT MATCH, HENCE MISS-------");
                            for(int n=0; n<WAYS; n++)
                              begin
                                if(exit==0 && LRU [set_index][n] == 0)
                                  begin
                                    exit = 1;

                                    if(command == 2)
                                      begin
                                        MESI[set_index][n] = Exclus;
                                        instruction_read = instruction_read+1;
                                        update_LRU(n);
                                        TAG[set_index][n] = tag_index;
                                        valid[set_index][n] = 1;
                                        if(mode == 1'b1)
                                          begin
                                            $display("--Communication with L2--");
                                            $display("Write to L2 <%0h>", tr_addr);
                                            $display("Read from L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                      end
                                  end
                              end
                          end
                      end
                  end

                8:

                  begin
                    foreach (MESI [x,y])
                      begin
                        TAG[x][y] = 0;
                        MESI[x][y] = Invalid;
                        LRU[x][y] = 0;
                        first_write_through[x][y] = 0;
                        valid[x][y] = 0;
                      end
                  end

                9:

                  begin
                    display_cache_contents();
                    display_report();
                  end
              endcase
            end
        end
      exit=0;
      valid_bit_count=0;
    end

task update_LRU;
    input int p;
    for( int q =0 ; q < WAYS ; q++ )
      begin
        if(q != p)
          begin
            if (LRU [set_index] [q] > LRU [set_index] [p])
	       LRU [set_index] [q] = LRU [set_index] [q]-1;
          end
      end
    LRU [set_index] [p] = WAYS-1;
  endtask

  task display_report;
    $display("---INSTRUCTION CACHE statistics---");
    $display("Total Number of instruction reads  = %0d", instruction_read);
    $display("Total Number of instruction writes = %0d", instruction_write);
    $display("Total Number of instruction hits   = %0d", instruction_hit);
    $display("Total Number of instruction misses = %0d", instruction_miss);
    if (instruction_hit+instruction_miss == 0)
      $display ("Denominator cannot be zero (ie, data_miss and data_hit is zero)");
    else
      begin
        instruction_hit_ratio = ( instruction_hit * 100 / ( instruction_hit + instruction_miss ) );
        $display("Instruction Cache HIT ratio = %f", instruction_hit_ratio);
        $display(" ");
      end
  endtask

  task display_cache_contents;
    $display("-------------------------------Contents of INSTRUCTION CACHE-------------------------------");
    $display("TRACE Address = %0h", tr_addr);
    $display("SET NUMBER          = %0h", set_index);
    $display("TAG3 = %0h\t\t TAG2 = %0h\t\t TAG1 = %0h\t\t TAG0 = %0h", TAG[set_index][3], TAG[set_index][2], TAG[set_index][1], TAG[set_index][0]);
    $display("STATE3 = %0d\t STATE2 = %0d\t STATE1 = %0d\t STATE0 = %0d" , MESI[set_index][3].name, MESI[set_index][2].name, MESI[set_index][1].name, MESI[set_index][0].name);
    $display("LRU3 = %0d\t\t LRU2 = %0d\t\t LRU1 = %0d\t\t LRU0 = %0d", LRU[set_index][3], LRU[set_index][2], LRU[set_index][1], LRU[set_index][0]);
    $display("VALID3 = %0d\t\t VALID2 = %0d\t\t VALID1 = %0d\t\t VALID0 = %0d", valid[set_index][3], valid[set_index][2], valid[set_index][1], valid[set_index][0]);
    $display(" ");
  endtask
endmodule

