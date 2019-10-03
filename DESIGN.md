# pe_tune

## Background

The default settings for Puppet Enterprise services are tuned, but not necessarily optimized for PE Infrastructure type and the combination of services competing for resources on each PE Infrastructure node.

## Allocates Resource Allocation

### Ratios, Minimums, and Maximums

With some exceptions, the `tune` command calculates settings for each service based upon a ratio of system resources (processors and/or memory) limited by a minimum and maximum.

The ratio, minimum, and maximum vary based upon the PE Infrastructure type and the PE services sharing resources on each PE Infrastructure host.

The supported minimum system resources for the `tune` command are 4 CPU / 8 GB RAM.

#### Standard Reference Architecture (Monolithic Master)

> CPU values are percentages and RAM values are megabytes.

##### Database Service (pe-postgresql)

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```

##### PuppetDB Service (pe-puppetdb)

```
percent_cpu_puppetdb = 0.25
minimum_cpu_puppetdb = 1
maximum_cpu_puppetdb = (CPU * 0.50)
```

```
percent_ram_puppetdb = 0.10
minimum_ram_puppetdb = 512
maximum_ram_puppetdb = 8192
```

With Compilers, the following change, as PuppetDB on the Master will be expected to handle requests from PuppetServer services on multiple Compilers, while PuppetServer on the Master will process catalog requests only for other PE Infrastructure hosts.

```
percent_cpu_puppetdb = 0.50
```

```
percent_ram_puppetdb = 0.20
```

##### Console Service (pe-console-services)

```
percent_ram_console = 0.08
minimum_ram_console = 512
maximum_ram_console = 1024
```

##### Orchestrator Service (pe-orchestration-services)

```
percent_ram_orchestrator = 0.08
minimum_ram_orchestrator = 512
maximum_ram_orchestrator = 1024
```

With PE 2019.2.x, the processor and memory associated with one jruby is reallocated from PuppetServer to Orchestrator, as it has jrubies and requires (estimated) one processor and additional memory.

##### ActiveMQ Service (pe-activemq)

```
percent_ram_activemq = 0.08
minimum_ram_activemq = 512
maximum_ram_activemq = 1024
```

ActiveMQ (used by MCollective) is deprecated in PE 2018.x and removed in PE 2019.x.

##### PuppetServer Service (pe-puppetserver)

Since PuppetServer is allocated up to the remainder of system resources, it does not have explicit ratios.

```
minimum_cpu_puppetserver = 2
maximum_cpu_puppetserver = 24
```

Since ReservedCodeCache is limited to a maximum of 2 GB, and each jruby requires an estimated 128 MB of ReservedCodeCache, the maximum number of jrubies is effectively limited to a maximum of 24.

```
minimum_ram_puppetserver = 512
```

```
minimum_ram_code_cache = 128
maximum_ram_code_cache = 2048
```

```
ram_per_jruby = (512, 768, 1024) if total memory (4-7 GB, 8-16 GB, 16 GB+)
ram_per_jruby_code_cache = 128
```

PuppetServer jrubies are constrained based on both how many jrubies fit into unallocated memory and unallocated processors. PuppetServer memory is then set the amount of memory required for all jrubies.

##### Operating System and Other Services

```
cpu_reserved = 1
```

```
ram_reserved = (256, 512, 1024) if total memory (4-7 GB, 8-16 GB, 16 GB+)
```

> Any Replica should/would/will receive the same settings as the Primary Master, as a Replica is required to have the same system resources as the Primary Master.

#### Large Reference Architecture (Compilers)

##### PuppetDB Service (pe-puppetdb)

If this is a Compiler with PuppetDB, the following change ...

```
percent_cpu_puppetdb = 0.25
minimum_cpu_puppetdb = 1
maximum_cpu_puppetdb = 3
```

> In addition, garbage collection is disabled, as it should only be performed by PuppetDB on the Master.

##### PuppetServer Service (pe-puppetserver)

Same as the `PuppetServer Service (pe-puppetserver)` on a Master.

#### Legacy Split Architecture (Master)

Same as `Standard Reference Architecture (Monolithic Master)` minus allocations for the services not present.

#### Legacy Split Architecture (Console)

##### Console Service (pe-console-services)

```
percent_ram_console = 0.75
minimum_ram_console = 512
maximum_ram_console = 4096
```

#### Legacy Split Architecture (Database)

##### Database Service (pe-postgresql)

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```

##### PuppetDB Service (pe-puppetdb)

```
percent_cpu_puppetdb = 0.50
minimum_cpu_puppetdb = 1
maximum_cpu_puppetdb = (CPU * 0.50)
```

```
percent_ram_puppetdb = 0.25
minimum_ram_puppetdb = 512
maximum_ram_puppetdb = 8192
```

If PostgreSQL is not present (External PostgreSQL) the following change:

```
percent_ram_puppetdb = 0.50
```

#### Legacy Split Architecture (External PostgreSQL)

##### Database Service (pe-postgresql)

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```
