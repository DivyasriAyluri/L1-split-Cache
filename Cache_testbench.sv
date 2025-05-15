module Cache_tesbench;

  logic Clock = 0;
  logic reset = 0;
  logic mode;
  bit s = 0;
  logic [3:0] command;
  logic [31:0] tr_addr;
  int filename;
  string line;
  string tracefile;
  int read_file;

  cache_data DUT1 ( .Clock(Clock), .reset(reset), .command(command), .tr_addr(tr_addr), .data_read(data_read), .data_write(data_write), 
				.data_hit(data_hit), .data_miss(data_miss), .mode(mode), .s(s) );
  cache_instruction DUT2 ( .Clock(Clock), .reset(reste), .command(command), .tr_addr(tr_addr), .instruction_read(instruction_read), .instruction_write(instruction_write), 
				.instruction_hit(instruction_hit), .instruction_miss(instruction_miss), .mode(mode), .s(s));

  always #10 Clock =~ Clock;

  initial
    begin
      @(negedge Clock);
      reset = 1;
      @(negedge Clock);
      reset = 0;

      if ($value$plusargs("Tracefile=%s", tracefile))
      filename = $fopen(tracefile,"r");
      
      if(filename==0)
        begin
          $display("Trace file not exist");
          $stop;
        end

      if ($test$plusargs("Mode"))
    	mode=0;
      else
    	mode=1;

      while(!$feof(filename))
        @(negedge Clock)
        begin
          read_file = $fgets( line , filename );
          $display("         ");
          $display("%s",line);

          read_file = $sscanf(line,"%d %h", command, tr_addr);
          if(read_file != 2)
            begin
              $display("Trace filename formatting is not correct");
              command=4'bx;
            end
        end
      $fclose(filename);
	s = 1;
      #33
      $stop;
    end
endmodule
