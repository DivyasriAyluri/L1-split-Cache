vlib work
vlog -reportprogress 300 -work work Cache_data.sv +acc
vlog -reportprogress 300 -work work Cache_instruction.sv +acc
vlog -reportprogress 300 -work work Cache_testbench.sv +acc
vsim -voptargs="+acc" work.Cache_tesbench +Tracefile=tracefile.txt
run -all