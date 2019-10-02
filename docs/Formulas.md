# How pe_tune calculates values

## Memory

### Minimums and Maximums
in MBs
puppetserver min = 512  
code_cache min   = 128  
code_cache max   = 2048  
database min     = 2048  
database max     = 16384  
puppetdb min     = 512  
puppetdb max     = 8192  
orchestrator min = 512  
orchestrator max = 1024  
console min      = 512  
console max      = 1024  
activemq min     = 512  
activemq max     = 1024  

###Standard ref arch (single host)

master Memory = 
1GB os + 25% database + 10% puppetdb + 8% orch + 8% console + 8% mco(if present) 

lovejoy and on, orchestrator gets extra ram equal to one puppetserver jruby (see below)

puppet server and puppet server code cache divide up whatever is leftover as follows:

Mem per jruby= 512, 768, 1024 (Ram on host:8 gb, 16gb, 32gb)
mem per jruby code cache = 128  (pre jruby9k 0)
jruby instances = leftover mem / (mem per jruby + mem per jruby code cache)
code cache = rjuby instances * mem per jruby code cache 
puppet server mem = rjuby instances * mem per jruby

###Large ref arch (single master plus compilers)

master memory = 
1GB os + 25% database + 20% puppetdb + 8% orch + 8% console + 8% mco(if present)  
puppetdb memory doubled from standard ref arch

compiler Memory = 
1GB os + 25% database + 10% puppetdb + 8% orch + 8% console + 8% mco(if present) 

lovejoy (2019.2) and on, orchestrator gets extra ram equal to one puppetserver jruby

puppet server and puppet server code cache gets whatever is leftover including any memory for a component that isn’t installed on the master.  

Mem per jruby= 512, 768, 1024 (8gb ram, 16 gb, 32gb)
mem per jruby code cache = 128  (pre jruby9k 0)
leftover mem / (mem per jruby + mem per jruby code cache) = jruby instances
code cache = rjuby instances * mem per jruby code cache 
puppet server mem = rjuby instances * mem per jruby

###XL (master, compilers, standalone postgres with puppetdb)
master/compiler same as large

puppetdb/postgres host:
puppetdb 25%
postgres 25% 
maintenance_work_mem = 33% max 1GB = 1024MB
work_mem = 8MB
autovacuum_work_mem = mainenance_work_mem / 2 = 512MB

##Ad hoc installs (like split)
Not covered.  But they will generally follow the formula above that they are most similar with.  And in the case of the master, memory for any service not on the master is given to puppet server.

## CPU
coming soon