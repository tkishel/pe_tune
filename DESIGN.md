# pe_tune

## Background

The default settings for Puppet Enterprise services are tuned, but not necessarily optimized for PE Infrastructure type and the combination of PE services competing for system resources on each PE Infrastructure host.

The `tune` command outputs optimized settings for Puppet Enterprise services based upon available system resources.

The command expects that you have provisioned the PE Infrastructure hosts with the system resources required to handle the workload, given agent count and code and environment complexity.

## Methodology

1. Query PuppetDB for PE Infrastructure hosts (query for declared PE classes)
1. Identify PE Infrastructure type: Standard, Large, Extra Large (legacy: Split)
1. Query PuppetDB for CPU and RAM facts for each PE Infrastructure host (query for processors, memory)
1. Output settings for PE services for each PE Infrastructure host (as parameters for the declared PE classes)

## Resource Allocation

### Ratios, Minimums, and Maximums

The `tune` command calculates settings for each service based upon a ratio of system resources (processors and/or memory) limited by a minimum and maximum.

The ratio, minimum, and maximum vary based upon the PE Infrastructure type and the combination of PE services competing for system resources on each PE Infrastructure host.

The minimum system resources for the `tune` command to function are 4 CPU / 8 GB RAM.

Notes:

> The following CPU values are percentages, and RAM values are megabytes.

> Any Replica should/would/will receive the same settings as the Primary Master, as a Replica is required to have the same system resources as the Primary Master.


#### Standard Reference Architecture

A Standard Reference Architecture is a Master-only install.

##### <a name="Standard-Master">Master</a>

Allocations are calculated in the following order.

###### <a name="Standard-Database">Database Service (pe-postgresql)</a>

```
CPU No Allocation
```

```
RAM Percent =  0.25
RAM Minimum =  2048
RAM Maximum = 16384
```

If the total number of potential database connections from all PuppetDB services exceeds the default, we increase `max_connections` by the number of potential database connections times `1.10`.

###### <a name="Standard-PuppetDB">PuppetDB Service (pe-puppetdb)</a>

```
CPU Percent = 0.25
CPU Minimum =    1
```

```
RAM Percent = 0.10
RAM Minimum =  512
RAM Maximum = 8192
```

###### Console Service (pe-console-services)

```
CPU No Allocation
```

```
RAM Percent = 0.08
RAM Minimum =  512
RAM Maximum = 1024
```

###### Orchestrator Service (pe-orchestration-services)

```
CPU No Allocation
```

```
RAM Percent = 0.08
RAM Minimum =  512
RAM Maximum = 1024
```

In PE 2019.2.x, Orchestrator has JRubies and is allocated additional memory as follows.


```
RAM Percent = 0.10
RAM Maximum =  N/A
```

Orchestrator JRubies do not require a CPU allocation as the are bound by I/O.
But we limit the number of Orchestrator JRubies based upon how many fit into the memory allocated to Orchestrator.

```
minimum jrubies orchestrator = 1
maximum jrubies orchestrator = 4
maximum jrubies orchestrator limited by memory = (allocated memory / memory per jruby)
orchestrator_jruby_max_active_instances        = (maximum jrubies orchestrator limited by memory).clamp(minimum jrubies orchestrator, maximum jrubies puppetserver orchestrator)
```


###### ActiveMQ Service (pe-activemq) *

```
CPU No Allocation
```

```
RAM Percent = 0.08
RAM Minimum =  512
RAM Maximum = 1024
```

\* ActiveMQ (used by MCollective) is deprecated in PE 2018.x and removed in PE 2019.x.

###### Puppet Server Service (pe-puppetserver)

Since PuppetServer is allocated the remainder of system resources, it does not have explicit ratios of CPU or RAM, or a maximum of RAM.

```
CPU Percent = N/A
CPU Minimum =   2
CPU Maximum =  24
```

Since ReservedCodeCache is limited to a maximum of 2 GB, and each JRuby requires an estimated 96 MB of ReservedCodeCache, the maximum number of JRubies is effectively limited to 24.

```
RAM Percent Heap = N/A
RAM Minimum Heap = 512
```

```
RAM Percent Reserved Code Cache =  N/A
RAM Minimum Reserved Code Cache =  128
RAM Maximum Reserved Code Cache = 2048
```

```
RAM Heap Per JRuby                = (512, 768, 1024) when RAM equals (4-7 GB, 8-16 GB, 16 GB+)
RAM Reserved Code Cache Per JRuby = 96
```

Puppet Server JRubies are constrained based on both how many JRubies fit into unallocated memory and unallocated processors (one JRuby per processor).
Puppet Server memory is then set to the amount of memory required for the total calculated number of JRubies.

```
minimum jrubies puppetserver = 2
maximum jrubies puppetserver = 24
maximum jrubies puppetserver limited by processors = (available processors).clamp(minimum jrubies puppetserver, maximum jrubies puppetserver)
maximum jrubies puppetserver limited by memory     = (available memory / (memory per jruby + memory per jruby reserved code cache))
puppetserver_jruby_max_active_instances            = (maximum jrubies puppetserver limited by memory).clamp(minimum jrubies puppetserver, maximum jrubies puppetserver limited by processors)
```

###### Operating System and Other Services

```
CPU Reserved = 1
```

```
RAM Reserved Percentage = 0.20
```


#### Large Reference Architecture

A Large Reference Architecture is a Master plus Compilers.

##### <a name="Large-Master">Master</a>

Calculations for the Master in a Large Reference Architecture use the same algorithms used for the [Standard Reference Architecture Master](#Standard-Master) with the following exceptions:

```
PuppetDB CPU Percent = 0.50 # up from 0.25
```

```
PuppetDB RAM Percent = 0.15 # up from 0.10
```

Rationale:

Puppet Server on the Master will process catalog requests only for PE Infrastructure hosts.
PuppetDB on the Master is expected to handle requests from the Puppet Server services on multiple Compilers that by definition serve more agents than the Standard Reference Architecture.

##### <a name="Large-Compilers">Compilers</a>

Calculations for Compilers in a Large Reference Architecture use the same algorithms used for the [Standard Reference Architecture Master](#Standard-Master) with the following exceptions.

```
PuppetDB CPU Maximum = 3
```

Compilers in a Large Reference Architecture include a local PuppetDB service.
The local PuppetDB service connects to the same PostgreSQL service as the PuppetDB service on the Master.
We lower the local PuppetDB allocation of CPU to enforce a limited number of connections to PostgreSQL, preventing an overallocation of connections to PostgreSQL.
In addition, we disable the local PuppetDB service garbage collection, as garbage collection is already performed by the PuppetDB service on the Master.


#### Extra Large Reference Architecture

An Extra Large Reference Architecture is a Master plus Compilers with PuppetDB and PostgreSQL services on a PuppetDB host.

##### Master

Calculations for the Master in an Extra Large Reference Architecture use the same algorithms used for the [Large Reference Architecture Master](#Large-Master)

##### Compilers

Calculations for Compilers in an Extra Large Reference Architecture use the same algorithms used for the [Large Reference Architecture Compilers](#Large-Compilers)

##### PuppetDB Host

Calculations for the PuppetDB Host use the same algorithms used for the [Standard Reference Architecture Master](#Standard-Master).

The below are the same settings for these two services as would be seen on a Standard Reference Architecture Master.

###### Database Service (pe-postgresql)

Same as [Standard Reference Architecture Database Service (pe-postgresql)](#Standard-Database)

###### PuppetDB Service (pe-puppetdb)

Same as [Standard Reference Architecture PuppetDB Service (pe-puppetdb)](#Standard-PuppetDB)


#### Legacy Split Architecture

##### Master

Calculations for a Split Master use the same algorithms used for the [Standard Reference Architecture Master](#Standard-Master) minus allocations for the services moved to the other hosts.

##### Console Host

###### Console Service (pe-console-services)

```
CPU No Allocation
```

```
RAM Percent = 0.75
RAM Minimum =  512
RAM Maximum = 4096
```

##### Database Host

###### Database Service (pe-postgresql)

```
CPU No Allocation
```

```
RAM Percent =  0.25
RAM Minimum =  2048
RAM Maximum = 16384
```

###### PuppetDB Service (pe-puppetdb)

```
CPU Percent = 0.50
CPU Minimum =    1
```

```
RAM Percent = 0.25
RAM Minimum =  512
RAM Maximum = 8192
```

If PostgreSQL is moved to an External PostgreSQL Host the following change:

```
PuppetDB RAM Percent = 0.50
```

##### External PostgreSQL Host

###### Database Service (pe-postgresql)

```
RAM Percent =  0.25
RAM Minimum =  2048
RAM Maximum = 16384
```
