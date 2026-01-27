# Redox OS Kernel Logs
How can I access the kernel logs? 

  1. GUI Mode (what you're currently seeing)                                                        
                                                                                                    
  ./run-dev.sh -g     # Opens window + serial in terminal                                           
  # or
  ./run-dev.sh -tg    # Tmux + GUI window                                                           
  This shows:                                                                                       
  - VGA/framebuffer console in the QEMU window (may have different messages)                        
  - Serial console in your terminal                                                                 
                                                                                                    
  2. Log QEMU output to file                                                                        
                                                                                                    
  Modify the QEMU command to add logging:                                                           
  ./run-dev.sh -t -d &                                                                              
  # Then redirect serial output:
  tmux pipe-pane -t redox-dev -o "cat >> /tmp/redox-boot.log"   
  NO This only copies the visible locks from the terminal, not the one from the GUI 

 This question is still open. The above are not solutions 
 
 System /scheme/logging doesn't work either  It's notoriously flaky and it doesn't write anything there anyways  
 dmsg is not available on Redox. 