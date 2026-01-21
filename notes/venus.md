Venus Driver prepared in the host /opt/other/qemu as well as here. 
                                                                  
  1. Venus blob creation now automatically rounds size up to 16KB                                                            
  2. SGL allocator supports custom alignment via new_aligned()                                                               
  3. DMA allocator supports custom alignment via zeroed_aligned()                                                            
  4. Kernel buddy allocator naturally returns 16KB-aligned memory for 4-page allocations                                     
                                                                                                                             
  Usage Example                                                                                                              
                                                                                                                             
  // Creating a 16KB-aligned SGL for Venus                                                                                   
  let sgl = Sgl::new_aligned(size, VENUS_BLOB_ALIGN_USIZE)?;                                                                 
                                                                                                                             
  // Creating 16KB-aligned DMA buffer                                                                                        
  let dma = Dma::zeroed_aligned(VENUS_BLOB_ALIGN_USIZE)?;                                                                    
                                                                                                                             
  // Blob creation automatically aligns to 16KB                                                                              
  adapter.create_blob(blob_mem, blob_flags, blob_id, size)?;  