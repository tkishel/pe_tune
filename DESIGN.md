# pe_tune

## Background

The default settings for Puppet Enterprise services are tuned, but not necessarily optimized for PE Infrastructure type and the combination of PE services competing for system resources on each PE Infrastructure host.

## Methodology

1. Query PuppetDB for PE Infrastructure Hosts (query for declared PE classes)
1. Query PuppetDB for CPU and RAM facts for PE Infrastructure Hosts (query for processors, memory)
1. Identify PE Infrastructure type: Standard, Large, Extra Large (legacy: Split)
1. For each PE Infrastructure Host, output settings for PE services (as parameters for the declared PE classes)

## Resource Allocation

### Ratios, Minimums, and Maximumsw

With some exceptions, the `tune` command calculates settings for each service based upon a ratio of system resources (processors and/or memory) limited by a minimum and maximum.

The ratio, minimum, and maximum vary based upon the PE Infrastructure type and the PE services competing for system resources on each PE Infrastructure host.

The minimum system resources for the `tune` command are 4 CPU / 8 GB RAM.

Notes:

> The following CPU values are percentages, and RAM values are megabytes.

> Any Replica should/would/will receive the same settings as the Primary Master, as a Replica is required to have the same system resources as the Primary Master.

#### Standard Reference Architecture

A Standard Reference Architecture is a Master-only install.

##### <a name="Standard-Master">Master</a>

###### <a name="Standard-Database">Database Service (pe-postgresql)</a>

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```

###### <a name="Standard-PuppetDB">PuppetDB Service (pe-puppetdb)</a>

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

###### Console Service (pe-console-services)

```
percent_ram_console = 0.08
minimum_ram_console = 512
maximum_ram_console = 1024
```

###### Orchestrator Service (pe-orchestration-services)

```
percent_ram_orchestrator = 0.08
minimum_ram_orchestrator = 512
maximum_ram_orchestrator = 1024
```

With PE 2019.2.x, the processor and memory associated with one jruby is reallocated from PuppetServer to Orchestrator, as Orchestrator has jrubies and requires (estimated) one processor and additional memory.

###### ActiveMQ Service (pe-activemq)

```
percent_ram_activemq = 0.08
minimum_ram_activemq = 512
maximum_ram_activemq = 1024
```

ActiveMQ (used by MCollective) is deprecated in PE 2018.x and removed in PE 2019.x.

###### PuppetServer Service (pe-puppetserver)

Since PuppetServer is allocated up to the remainder of system resources, it does not have explicit ratios.

```
minimum_cpu_puppetserver = 2
maximum_cpu_puppetserver = 24
```

Since ReservedCodeCache is limited to a maximum of 2 GB, and each jruby requires an estimated 85 MB of ReservedCodeCache, the maximum number of jrubies is effectively limited to a maximum of 24. But note we allocate 128 MB of reserved code cache per jruby when possible.

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

PuppetServer jrubies are constrained based on both how many jrubies fit into unallocated memory and unallocated processors (one jruby per processor).
PuppetServer memory is then set to the amount of memory required for the total calculated number of jrubies.

```
possible_jrubies_by_ram = (unreserved ram) / (ram_per_jruby + ram_per_jruby_code_cache)
# rjubies capped by (unreserved cpu) or maximum_cpu_puppetserver, whichever is less.
puppetserver_ram = jrubies * ram_per_jruby
code_cache_ram = jrubies * ram_per_jruby_code_cache
```

###### Operating System and Other Services

```
cpu_reserved = 1
```

```
ram_reserved = (256, 512, 1024) if total memory (4-7 GB, 8-16 GB, 16 GB+)
```

#### Large Reference Architecture

A Large Reference Architecture is a Master plus compilers install.

##### <a name="Large-Master">Master</a>

Calculations for the Master in a Large Reference Architecture use the same algorithm as for the [Standard Reference Architecture Master](#Standard-Master) with the following exceptions:

PuppetServer on the Master will process catalog requests only for other PE Infrastructure hosts.
PuppetDB on the Master will be expected to handle requests from PuppetServer services on multiple Compilers that together are servicing more agents than the Standard Reference Architecture.
So resources on the master are transferred from PuppetServer to PuppetDB as follows.
```
percent_cpu_puppetdb = 0.50 # up from 0.25

percent_ram_puppetdb = 0.20 # up from 0.10
```

##### <a name="Large-Compilers">Compilers</a>

Compilers are configured by the same algorithm used for the [Standard Reference Architecture Master](#Standard-Master).

With PuppetDB on Compilers, each PuppetDB connects to the same PostgresSQL service as the PuppetDB on the Master does.

We lower each PuppetDB's allocation of CPU to create a limited number of connections to PostgresSQL, preventing an overallocation of connections to PostgresSQL.

In addition, PuppetDB garbage collection is disabled on Compilers, as garbage collection is/should only be performed by one PuppetDB (on the Master).

```
maximum_cpu_puppetdb = 3 # was (CPU * 0.50)
```

#### Extra Large Reference Architecture

An Extra Large Reference Architecture is a Master plus compilers with a standalone PuppetDB and PostgresSQL service on the PuppetDB host.

##### Master

Calculations for the Master in an Extra Large Reference Architecture use the same algorithm used for the [Large Reference Architecture Master](#Large-Master)

##### Compilers

Calculations for the Compilers in an Extra Large Reference Architecture use the same algorithm used for the [Large Reference Architecture Compilers](#Large-Compilers)

##### PuppetDB Host

Calculations for the PuppetDB Host use the same algorithm as for the Standard Reference Architecture.

The below are the same settings for these two services as would be seen on a Standard Reference Architecture Master.

###### Database Service (pe-postgresql)

Same as [Standard Reference Architecture Database Service (pe-postgresql)](#Standard-Database)

###### PuppetDB Service (pe-puppetdb)

Same as [Standard Reference Architecture PuppetDB Service (pe-puppetdb)](#Standard-PuppetDB)

#### Legacy Split Architecture

##### Master

Same as [Standard Reference Architecture Master](#Standard-Master) minus allocations for the services not present.

##### Console Host

###### Console Service (pe-console-services)

```
percent_ram_console = 0.75
minimum_ram_console = 512
maximum_ram_console = 4096
```

##### Database Host

###### Database Service (pe-postgresql)

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```

###### PuppetDB Service (pe-puppetdb)

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

##### External PostgreSQL Host

###### Database Service (pe-postgresql)

```
percent_ram_database = 0.25
minimum_ram_database = 2048
maximum_ram_database = 16384
```
