module cache_data

( Clock, reset, command, tr_addr, data_read, 
 data_write, data_hit, data_miss, mode, s );

  input logic reset;
  input logic [3:0]  command;       									// Command from trace file
  input logic [31:0] tr_addr;	  							     	// Address from trace file
  input logic mode;
  input bit s;
  input logic Clock;
  output real data_read, data_write, data_hit, data_miss;
  typedef enum {Modif,Exclus,Shared,Invalid} STATE;						//Declaring States

  parameter CACHE_LINE_SIZE = 64; 									// Total number of bytes in cache line
  parameter BYTE_OFFSET_BITS = $clog2 (CACHE_LINE_SIZE);						// Number of byte offset bits
  parameter SET_SELECT_BITS = $clog2 (SETS);	
  parameter ADDRESS_BITS = 32;								                 // Number of byte offset bits
  parameter TAG_BITS = ADDRESS_BITS - (SET_SELECT_BITS + BYTE_OFFSET_BITS);					// Number of TAG bits
  parameter LRU_BITS = $clog2 (WAYS);                                                                               // Number of LRU bits												// Total Number of Address Bits
  parameter SETS = 16*1024;										// Total number of TOTAL SETS
  parameter WAYS = 8;											// Total number of TOTAL WAYS
						

  real data_hit_ratio; 												
  logic [LRU_BITS-1:0] LRU[SETS-1:0][WAYS-1:0] = {default:3'b000};					// LRU bits per cache line - Default set to 000
  logic [TAG_BITS-1:0] TAG[SETS-1:0][WAYS-1:0];							// Tag bits per cache line
  bit valid[SETS-1:0][WAYS-1:0];
  bit dirty[SETS-1:0][WAYS-1:0];
  bit first_write_through [SETS -1: 0] [WAYS-1:0];

  STATE MESI[SETS-1 : 0][WAYS-1:0];
  int exit = 0;
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
          data_read = 0;
          data_write = 0;
          data_hit = 0;
          data_miss = 0;
          foreach (MESI [x,y])
            begin
              TAG[x][y] = 0;
              MESI[x][y] = Invalid;
              LRU[x][y] = 3'b000;
              first_write_through[x][y] = 0;
              valid[x][y] = 0;
              dirty[x][y] = 0;
            end
        end

      else
        begin

          if (command != 2)
            begin
              case(command)
                0, 1, 3, 4:
                  begin
                    exit = 0;
                    for(int m=0 ; m<WAYS; m++)
                      begin
                        if(valid[set_index][m] == 1)
                          valid_bit_count = valid_bit_count +1;
                      end

                    for (int i = 0 ; i<WAYS ; i++)
                      begin if ( (valid[set_index][i] == 0) && ( TAG[set_index][i] == tag_index) )
                          begin if(mode == 1'b1)
                                begin
					$display("------TAG BITS MATCH, HENCE HIT-------");
                           	 	$display("------Communication with L2------");
                            		$display("Data Cache : Write to L2 <%0h>", tr_addr);
                            		$display(" ");
				end
                            	update_LRU(i);
                           	valid[set_index][i] = 1;
                           	dirty[set_index][i] = 0;
					
                         end
                     end

                    for(int m=0 ; m<WAYS; m++)
                      begin

                        ///////////////************************************ IF TAG BITS MATCH - HIT *********************************/////////////////////
                        if((exit==0 && valid[set_index][m] == 1) && ( TAG[set_index][m] == tag_index) )
                          begin
                            exit = 1;
                            data_hit = data_hit+1;
                            $display("------TAG BITS MATCH, HENCE HIT-------");

                            //////////////////////////////--------------------MODIFIED STATE -----------------------///////////////////////////////////

                            if (MESI[set_index][m] == Modif)
                              begin
                                if (command == 0) 				// Read data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modif;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                    dirty[set_index][m]=1;
                                  end

                                else if (command == 1)			// Write data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modif;
                                    data_write = data_write + 1;
                                    update_LRU(m);
				    
                                    if (first_write_through [set_index][m]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("------Communication with L2------");
                                            $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (command == 3 || command == 4)			// ( Invalidate command from L2 OR Snooping )

                                  begin
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
				    
                                    if(command == 3)
                                      begin if(dirty[set_index][m] == 1)
                                          begin if(mode == 1'b1)
                                              begin
                                                $display("------Communication with L2------");
                                                $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                                $display(" ");
                                              end
                                            dirty[set_index][m]=0;
                                          end
                                      end
                                    if(command == 4)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", tr_addr);
                                            $display(" ");
					    $display("Data Cache : Read for Ownership from L2 <%0h>", tr_addr);
                                          end
					  data_hit = data_hit-1;
                                      end
                                    valid[set_index][m] = 0;
				
                                  end
                              end

                            //////////////////////////////--------------------EXCLUSIVE STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Exclus)
                              begin
                                if (command == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                    dirty[set_index][m]=0;
                                  end

                                else if (command == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modif;
                                    data_write = data_write + 1;
                                    update_LRU(m);
			            
                                    if (first_write_through [set_index][m]==0)
				    begin
                                    	first_write_through [set_index][m]=1;
                                    	dirty[set_index][m]=1;
				    end
                                 end

                                else if (command == 3 || command == 4)		// ( 3 - Invalidate command from L2 or snooping) )
                                  begin
                                    
                                        if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", tr_addr);
                                            $display(" ");					    
                                          end
					  data_hit = data_hit-1;
                                      
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
				    valid[set_index][m] = 0;
                                  end
                              end

                            //////////////////////////////--------------------SHARED STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Shared)
                              begin
                                if (command == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                  end

                                else if (command == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modif;
                                    data_write = data_write+1;
                                    update_LRU(m);
				     
                                    if (first_write_through [set_index][m]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin

                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end

                                        first_write_through [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (command == 3 || command == 4)			// ( 3 - Invalidate command from L2 or Snooping )

                                  begin if(command == 4)
                                      begin if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                      end
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
                                    valid[set_index][m] = 0;
                                  end
                              end
                          end  
                      end


                    ///////////////************************************ IF TAG BITS DON'T MATCH - MISS *********************************/////////////////////


                    if((valid_bit_count < WAYS) && (exit == 0))
                      begin
                        data_miss = data_miss+1;
                        $display("-----TAG BITS DONT MATCH - MISS-----");
                        for(int k=0; k<WAYS; k++)
                          begin
                            if(exit==0 && LRU[set_index][k] == 0 && valid[set_index][k] == 0)
                              begin
                                exit = 1;

                                if(command == 0)
                                  begin
                                    MESI[set_index][k] = Exclus;
                                    data_read = data_read+1;
                                    update_LRU(k);
				    
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k] = 0;
                                    if(mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Read from L2 <%0h>", tr_addr);
                                        $display(" ");
                                      end
                                  end

                                else if(command == 1)
                                  begin
                                    MESI[set_index][k] = Modif;
                                    data_write=data_write+1;
                                    update_LRU(k);
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k]=1;
                                    if (first_write_through [set_index][k]==0)
                                      begin
                                        if(mode == 1'b1)
                                          begin
                                            $display("--------------Communication with L2--------------");
                                            $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", tr_addr);
                                            $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][k]=1;
                                      end
                                  end

                                else if(command == 3)
                                  begin
                                    MESI[set_index][k] = Invalid;
                                    update_LRU(k); 
                                    valid[set_index][k] = 0;
                                  end

                                else if(command == 4)
                                  begin if(mode == 1'b1)
                                          begin
                                   	 $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", tr_addr);
                                  	end
				end
                              end
                          end
                      end

                    if((valid_bit_count==WAYS) && (exit == 0))
                      begin
                        data_miss = data_miss + 1;
                        $display("-----TAG BITS DONT MATCH - MISS-----");
                        for(int n=0; n<WAYS; n++)
                          begin if(exit==0 && LRU [set_index][n] == 0)
                              begin
                                exit = 1;

                                if(command == 0)
                                  begin
                                    MESI[set_index][n] = Exclus;
                                    data_read = data_read+1;
                                    update_LRU(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n]=0;
                                    if(mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                        $display("Data Cache : Read from L2 <%0h>", tr_addr);
                                        $display(" ");
                                      end
                                  end

                                else if(command == 1)
                                  begin
                                    MESI[set_index][n] = Modif;
                                    data_write=data_write+1;
                                    update_LRU(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n] = 1;
                                    if(mode == 1'b1)
                                      begin
                                        $display("---------------Communication with L2---------------");
                                        $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", tr_addr);
                                        $display(" ");
                                      end

                                    if (first_write_through [set_index][n]==0)
                                      begin if(mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", tr_addr);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][n]=1;
                                      end
                                  end

                                else if(command == 3)
                                  begin
                                    MESI[set_index][n] = Invalid;
                                    update_LRU(n); 
                                    valid[set_index][n] = 0;
                                  end

                                else if(command == 4)
                                    $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", tr_addr);
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
                        dirty[x][y] = 0;
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
      exit = 0;
      valid_bit_count = 0;
    end

  task update_LRU;
    input int s;
    for( int q =0 ; q < WAYS ; q++ )
      begin
        if(q != s)
          begin
            if (LRU [set_index] [q] > LRU [set_index] [q])
	       LRU [set_index] [q] = LRU [set_index] [q]-1;
	  end
      end
    LRU [set_index] [s] = WAYS-1;
  endtask

  task display_report;
    $display("-----DATA CACHE statistics-----");
    $display("Total Number of data reads  = %0d", data_read);
    $display("Total Number of data writes = %0d", data_write);
    $display("Total Number of data hits   = %0d", data_hit);
    $display("Total Number of data misses = %0d", data_miss);
    if ( data_hit + data_miss == 0 )
      $display ("Denominator cannot be zero (i.e, data_miss and data_hit is zero)");
    else
      begin
        data_hit_ratio = ( data_hit * 100 / ( data_hit + data_miss ) );
        $display("DATA CACHE HIT ratio = %f", data_hit_ratio);
        $display(" ");
      end
  endtask

  task display_cache_contents;
    $display("--------------------------------------------------------------------------------Contents of DATA CACHE--------------------------------------------------------------------------------");
    $display("TRACE ADDRESS = %0h", tr_addr);
    $display("SET NUMBER   = %0h", set_index);
    $display("TAG7 = %0h\t\t TAG6 = %0h\t\t TAG5 = %0h\t\t TAG4 = %0h\t\t TAG3 = %0h\t\t TAG2 = %0h\t\t TAG1 = %0h\t\t TAG0 = %0h", TAG[set_index][7], TAG[set_index][6], TAG[set_index][5], TAG[set_index][4], TAG[set_index][3], TAG[set_index][2], TAG[set_index][1], TAG[set_index][0]);
    $display("STATE7 = %0d\t STATE6 = %0d\t STATE5 = %0d\t STATE4 = %0d\t STATE3 = %0d\t STATE2 = %0d\t STATE1 = %0d\t STATE0 = %0d" ,MESI[set_index][7].name, MESI[set_index][6].name, MESI[set_index][5].name, MESI[set_index][4].name, MESI[set_index][3].name, MESI[set_index][2].name, MESI[set_index][1].name, MESI[set_index][0].name);
    $display("LRU7 = %0d\t\t LRU6 = %0d\t\t LRU5 = %0d\t\t LRU4 = %0d\t\t LRU3 = %0d\t\t LRU2 = %0d\t\t LRU1 = %0d\t\t LRU0 = %0d", LRU[set_index][7], LRU[set_index][6], LRU[set_index][5], LRU[set_index][4], LRU[set_index][3], LRU[set_index][2], LRU[set_index][1], LRU[set_index][0]);
    $display("DIRTY7 = %0d\t\t DIRTY6 = %0d\t\t DIRTY5 = %0d\t\t DIRTY4 = %0d\t\t DIRTY3 = %0d\t\t DIRTY2 = %0d\t\t DIRTY1 = %0d\t\t DIRTY0 = %0d", dirty[set_index][7], dirty[set_index][6], dirty[set_index][5], dirty[set_index][4], dirty[set_index][3], dirty[set_index][2], dirty[set_index][1], dirty[set_index][0]);
    $display("VALID7 = %0d\t\t VALID6 = %0d\t\t VALID5 = %0d\t\t VALID4 = %0d\t\t VALID3 = %0d\t\t VALID2 = %0d\t\t VALID1 = %0d\t\t VALID0 = %0d", valid[set_index][7], valid[set_index][6], valid[set_index][5], valid[set_index][4], valid[set_index][3], valid[set_index][2], valid[set_index][1], valid[set_index][0]);
    $display(" ");
  endtask
endmodule

