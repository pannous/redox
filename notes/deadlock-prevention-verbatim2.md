  The Fundamental Problem                                                                                                  
                                                                                                                           
  Redox's scheme architecture is essentially a distributed system inside an OS. Each scheme handler is an independent      
  process, and blocking IPC creates the same problems as distributed systems:                                              
                                                                                                                           
  1. No global state - No single entity knows all pending requests                                                         
  2. Partial failure - One scheme can fail while others continue                                                           
  3. Asynchronous communication - Message delivery is not instantaneous                                                    
                                                                                                                           
  Theoretical Prevention Approaches                                                                                        
                                                                                                                           
  1. Hierarchical Resource Ordering (Classical)                                                                            
                                                                                                                           
  Assign each scheme a level. Schemes can only call schemes at lower levels:                                               
                                                                                                                           
  Level 3: Applications (set-background, ping)                                                                             
  Level 2: Display, Network, Filesystem schemes                                                                            
  Level 1: Block devices, NIC drivers                                                                                      
  Level 0: Kernel primitives                                                                                               
                                                                                                                           
  Guarantee: No cycles possible by construction.                                                                           
                                                                                                                           
  Limitation: Limits expressiveness. What if display needs filesystem?                                                     
                                                                                                                           
  2. Session Types / Behavioral Types (Research)                                                                           
                                                                                                                           
  Encode the protocol in the type system. A scheme declares what messages it sends/receives and in what order:             
                                                                                                                           
  // Hypothetical type-level protocol                                                                                      
  type DisplayProtocol = Recv<OpenRequest,                                                                                 
                          Send<OpenResponse,                                                                               
                          Loop<Recv<IoctlRequest, Send<IoctlResponse>>>>>;                                                 
                                                                                                                           
  Rust could check at compile time that:                                                                                   
  - Clients follow the expected protocol                                                                                   
  - No message is left unanswered                                                                                          
  - No circular waits in the protocol graph                                                                                
                                                                                                                           
  Research: "Session Types for Rust" papers exist but aren't production-ready.                                             
                                                                                                                           
  3. Effect Systems (Research)                                                                                             
                                                                                                                           
  Track which schemes a function might call as part of its type:                                                           
                                                                                                                           
  // Hypothetical                                                                                                          
  fn render_image() -> Result<(), Error>                                                                                   
      requires [display, filesystem]  // Effect annotation                                                                 
  {                                                                                                                        
      // ...                                                                                                               
  }                                                                                                                        
                                                                                                                           
  The compiler builds a call graph of scheme dependencies and rejects programs with cycles.                                
                                                                                                                           
  4. Non-Blocking by Default (Architectural)                                                                               
                                                                                                                           
  Make all scheme operations async/non-blocking:                                                                           
                                                                                                                           
  // Instead of blocking:                                                                                                  
  let result = scheme.call(request)?;  // Blocks                                                                           
                                                                                                                           
  // Always async:                                                                                                         
  let future = scheme.call_async(request);                                                                                 
  // Process other requests while waiting                                                                                  
  loop {                                                                                                                   
      select! {                                                                                                            
          result = future => handle(result),                                                                               
          new_req = incoming => process(new_req),                                                                          
      }                                                                                                                    
  }                                                                                                                        
                                                                                                                           
  Key insight: Deadlocks require blocking. If nothing blocks, cycles don't cause hangs—just back-pressure.                 
                                                                                                                           
  This is the actor model (Erlang, Akka) approach. Redox could adopt it more fully.                                        
                                                                                                                           
  5. Deadlock Detection + Recovery (Runtime)                                                                               
                                                                                                                           
  Kernel maintains a wait-for graph of all blocked processes:                                                              
                                                                                                                           
  Process A waiting for → Scheme B                                                                                         
  Scheme B waiting for → Scheme C                                                                                          
  Scheme C waiting for → Process A  ← CYCLE DETECTED                                                                       
                                                                                                                           
  On cycle detection:                                                                                                      
  - Kill youngest process (database approach)                                                                              
  - Return EDEADLK to one participant                                                                                      
  - Log for debugging                                                                                                      
                                                                                                                           
  Limitation: Detection is reactive, not preventive.                                                                       
                                                                                                                           
  6. Capability-Based Scheme Access (Architectural)                                                                        
                                                                                                                           
  Processes can only call schemes they have explicit capabilities for:                                                     
                                                                                                                           
  // Process receives capabilities at spawn                                                                                
  fn main(caps: Capabilities) {                                                                                            
      let display = caps.get::<DisplayScheme>()?;  // Must have capability                                                 
      display.call(...);                                                                                                   
  }                                                                                                                        
                                                                                                                           
  The capability graph is known at spawn time. Kernel can check:                                                           
  - Does granting these capabilities create a potential cycle?                                                             
  - If so, reject the spawn or warn                                                                                        
                                                                                                                           
  What Would Work Best for Redox?                                                                                          
                                                                                                                           
  Given Redox's design, I'd suggest a combination:                                                                         
  ┌──────────────────────────┬────────┬──────────────────────────────────┐                                                 
  │         Approach         │ Effort │             Benefit              │                                                 
  ├──────────────────────────┼────────┼──────────────────────────────────┤                                                 
  │ Timeouts everywhere      │ Low    │ Already partial; complete it     │                                                 
  ├──────────────────────────┼────────┼──────────────────────────────────┤                                                 
  │ Wait-for graph detection │ Medium │ Catch cycles at runtime          │                                                 
  ├──────────────────────────┼────────┼──────────────────────────────────┤                                                 
  │ Async-first scheme API   │ High   │ Eliminates root cause            │                                                 
  ├──────────────────────────┼────────┼──────────────────────────────────┤                                                 
  │ Hierarchical levels      │ Medium │ Simple, effective for most cases │                                                 
  └──────────────────────────┴────────┴──────────────────────────────────┘                                                 
  The async-first approach is most aligned with modern OS research (seL4, Fuchsia) but requires significant API changes.   
                                                                                                                           
  The Login Shell Bug                                                                                                      
                                                                                                                           
  The notes mention a specific bug: processes from login shell don't reach schemes. This isn't a deadlock—it's a namespace 
  routing bug. The scheme namespace visible to login shell children may differ from init's namespace.                      
                                                                                                                           
  This is actually a capability problem: the login shell process doesn't have (or isn't passing) the right scheme handles  
  to its children.                                                                                                         
                       