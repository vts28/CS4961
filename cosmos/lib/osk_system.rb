###############################################################################
# OSK System
#
# Notes:
#   1. System is the primary entry point into the OpenSatKit framework. It
#      serves as a central access point for all OSK configurations and
#      definitions. Whenever possible it uses existing COSMOS definitions
#      to prevent multiple definitions
#   2. System is designed as a Singleton 
#
# License:
#   Written by David McComas, licensed under the copyleft GNU General Public
#   License (GPL).
#
###############################################################################

require 'cosmos'
require 'file_transfer'
require 'osk_flight'

module Osk
   
   class System
   
      @@instance = nil
      
      # 
      # File_transfer configured for flight-ground file transfer protocol which
      # typically would be TFTP or CFDP
      #
      attr_reader :file_transfer
      
      def initialize
         raise "Osk::System created twice" unless @@instance.nil?
         init_variables
         @@instance = self
      end # End initialize()
      
      def init_variables
         @file_transfer = TftpFileTransfer.new()
      end # End init_variables()

      ####################################################################
      ##                     cFS Management Methods                     ##
      ####################################################################
     
      # 
      # Check if cFS is running and start cFS with or without a user prompt
      #      
      def self.check_n_start_cfs(prompt = true)
         cfs_started = false
         if (not Osk::System.cfs_running?)
            if (prompt)
               continue = message_box("The flight software is not running. Select <Yes> to start the FSW and run the script.  A terminal window will be created to run the FSW. Enter your user password when prompted.",Osk::MSG_BUTTON_YES,Osk::MSG_BUTTON_NO,false) #puts "continue = #{continue}"
               return unless continue == Osk::MSG_BUTTON_YES
            end
            Osk::System.start_cfs  # Enables telemetry
            cfs_started = true 
         end
         return cfs_started 
      end 
      
      # 
      # Check for cFS existing instances
      #      
      def self.cfs_running?
            
         core = `pgrep core`
         #puts core + " len = #{core.length}"
         return (core.length > 1)
      
      end
      
      # 
      # Start the cFS and enable telemetry
      #      
      def self.start_cfs()
         
         # Start the cFS
         spawn("xfce4-terminal --title=\"core Flight System\" --default-working-directory=\"#{Osk::CFS_EXE_DIR}\" --execute sudo ./core-cpu1")
         #spawn("xfce4-terminal --default-working-directory=""#{Osk::CFS_EXE_DIR}"" --execute echo #{Osk::PASSWORD} | sudo ./core-cpu1""")
         #~Osk::system.connect_to_local_cfs  # Sometimes previous session left in a bad state

         wait(4)  # Give some time to type in password
         
         # Enable telemetry
         done = false
         attempts = 0
         while (!done)
            core = `pgrep core`
            if (core.length > 1)
               wait(2)
               cmd("KIT_TO ENABLE_TELEMETRY")
               done = true
               #puts core + " len = #{core.length}"
            else
               attempts += 1
               if (attempts < 5)
                  wait (4)
               else
                  done = true
               end
            end
            #~seq_cnt = tlm("CFE_ES #{Osk::TLM_STR_HK_PKT} #{Ccsds::PRI_HDR_SEQUENCE}")
            #~puts core + " len = #{core.length}"
            #~if ( tlm("CFE_ES #{Osk::TLM_STR_HK_PKT} #{Ccsds::PRI_HDR_SEQUENCE}") != seq_cnt)
            #~   done = true
            #~else
            #~   begin
            #~      cmd("KIT_TO ENABLE_TELEMETRY")
            #~   rescue
            #~      Osk::system.connect_to_local_cfs
            #~   end
            #~   attempts += 1
            #~   if (attempts < 5)
            #~      wait (4)
            #~   else
            #~      done = true
            #~   end
            #~end   
         end # while ! done
         #~puts "attempt #{attempts}"
      
      end # start_cfs()      

      
      # 
      # Stop all instances of the cFS
      #
      def self.stop_cfs()
         stopped_instances = false
         core = `pgrep core`  # If cFS instances are running this creates a string with with process IDs such as "xxxxx\nxxxxx\n" where xxxxx=Process ID
         if (core.length > 1)
            message_box("Instances of the cFS are running. You will be prompted to kill each instance. Enter your user password when prompted.",Osk::MSG_BUTTON_CONT,false)
            sh_file = "kill_cfs.sh"
            sh_path_file = File.join(Osk::OSK_CFS_DIR,sh_file)
            begin
               File.open(sh_path_file,"w") do |f|
                  f.write ("#!/bin/bash\n")
                  f.write ("set -o verbose\n")
                  core.split.each do |pid|
                     f.write ("sudo kill #{pid}\n")
                  end
               end # File
               spawn("xfce4-terminal --title=\"Kill cFS Instances\" --default-working-directory=\"#{Osk::OSK_CFS_DIR}\" --execute ./#{sh_file}")
               stopped_instances = true
               #echo #{Osk::PASSWORD} | sudo -S kill #{core}`  # Echo supplies the password to sudo. Can only do this if user can store their password
            rescue Exception => e
               puts e.message
               puts e.backtrace.inspect  
            end

         end # If cores running
         return stopped_instances
      end # stop_cfs()
      

      ###################################################################
      ##                     42 Management Methods                     ##
      ###################################################################

      # 
      # Start the 42 simulator and connect FSW I42 app
      #      
      def self.start_42(display_scr=false)
         
         spawn("xfce4-terminal --title=\"42 Simulator\" --default-working-directory=\"#{Cosmos::USERPATH}/#{Osk::REL_DIR_42}\" --execute ./42 OSK")
         wait(2)
         Osk::flight.send_cmd("I42","CONNECT_42")
     
         display("CFS_KIT SIM_42_SCREEN",1500,50) if display_scr
      
      end # start_42()

      # 
      # Start the 42 simulator and connect FSW I42 app
      #      
      def self.stop_42
      
         Osk::flight.send_cmd("I42","DISCONNECT_42")
      
      end # stop_42()


      # Stop the COSMOS cmd-tlm-server. This is an ungraceful
      # termination. It kills the process.
      def self.stop_cmd_tlm_server()
      
         pids = `ps H -C ruby -o \'pid comm\'`   
         #puts pids
         pids.each_line do |line|
            if line.include? "cmd_tlm_server"  
               #puts "Found server PID: " + line
               cmd_tlm_pid = line.split[0]
               `echo osk | sudo -S kill #{cmd_tlm_pid}` # Echo supplies the password
            end
         end
         
      end # stop_cmd_tlm_server()
      
      ######################################################################
      ##                     PiSat Management Methods                     ##
      ######################################################################
      
      def switch_local_to_pisat_cfs(host_ip_addr=HOST_IP_ADDR, pisat_ip_addr=PISAT_IP_ADDR)
   
         if (interface_state(COSMOS_CFS_INT) == 'CONNECTED')
            # Done in case switch can be performed without shutting down an interface  
            cmd("KIT_TO ENABLE_TELEMETRY with IP_ADDR #{NULL_IP_ADDR}")
	         wait(2)
            disconnect_interface(COSMOS_CFS_INT)
            wait(5)
         end
         connect_interface(COSMOS_CFS_INT,pisat_ip_addr,CFS_CMD_PORT,CFS_TLM_PORT,nil,nil,128,nil,nil)
         wait(5)
         @file_transfer = TftpFileTransfer.new(pisat_ip_addr)
         cmd("KIT_TO ENABLE_TELEMETRY with IP_ADDR #{host_ip_addr}")
         wait(2)
         cmd("TFTP INIT_SOCKET with IP_ADDR #{host_ip_addr}")         
         #Cosmos.run_process("ruby tools/CmdSender -p \"KIT_TO ENABLE_TELEMETRY\"")
         #connect_interface("CFS_INT",udp_cs_interface.rb,192.168.0.1,1234,1235,nil,nil,128,nil,nil)
         #map_target_to_interface("CS","CFS_PI_INT")      
      end # End connect_to_pisat()
      
      def switch_pisat_to_local_cfs()

         if (interface_state(COSMOS_CFS_INT) == 'CONNECTED')
            # Done in case switch can be performed without shutting down an interface  
            cmd("KIT_TO ENABLE_TELEMETRY with IP_ADDR #{NULL_IP_ADDR}")
	         wait(2)
            disconnect_interface(COSMOS_CFS_INT)
            wait(5)
         end
         connect_interface(COSMOS_CFS_INT,"localhost",CFS_CMD_PORT,CFS_TLM_PORT,nil,nil,128,nil,nil)
         wait(5)
         @file_transfer = TftpFileTransfer.new(COSMOS_IP_ADDR)
         cmd("KIT_TO ENABLE_TELEMETRY with IP_ADDR #{COSMOS_IP_ADDR}")
         wait(2)
         cmd("TFTP INIT_SOCKET with IP_ADDR #{COSMOS_IP_ADDR}")         

      end # End connect_to_pisat()
      
      def connect_to_local_cfs()

         if (interface_state(COSMOS_CFS_INT) != 'CONNECTED')
            connect_interface(COSMOS_CFS_INT,"localhost",CFS_CMD_PORT,CFS_TLM_PORT,nil,nil,128,nil,nil)
         end
   
      end # End connect_to_pisat()

   end # System class
   
   # An instance of system is created outside of the module
   class << self; attr_accessor :system; end

end # Module Osk


Osk.system = Osk::System.new()
Osk.flight = Osk::Flight.new()

