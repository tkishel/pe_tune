# pe_tune

#### Table of Contents

1. [Module Description - What the module does and why it is useful](#module-description)
1. [Setup - The basics of getting started with this module](#setup)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
1. [Limitations - OS compatibility, etc.](#limitations)

## Module Description

This module provides a `puppet infrastructure tune` face for optimizing the settings
for Puppet Enterprise services, based upon hardware resources.

See DESIGN.md for more information.

## Setup

Install the module on the Primary Master:

```
git clone https://github.com/tkishel/pe_tune.git /etc/puppetlabs/code/environments/production/modules/pe_tune
puppet agent -t
```

Or download, install, and run this module (on the Primary Master) as a script:

```
curl -O https://raw.githubusercontent.com/tkishel/pe_tune/master/lib/puppet_x/puppetlabs/tune.rb
chmod +x tune.rb
./tune.rb
```

## Usage

1. Run `puppet infrastructure tune` on the Primary Master.
1. Verify the settings.
1. Add the settings to Hiera.
1. Remove duplicate settings from the Console.
1. Run `puppet agent -t` on each Puppet Enterprise infrastructure host to apply the settings.

## Reference

The `puppet infrastructure tune` face reads infrastructure settings on the Primary Master,
queries PuppetDB for node group membership to identify infrastructure hosts,
queries PuppetDB for processor and memory facts for each infrastructure host,
and outputs optimizing settings for each infrastructure host as Hiera YAML data.

By default, settings are output to STDOUT.

For example:

```
[root@master ~]# puppet infrastructure tune
### Puppet Infrastructure Summary: Found a Monolithic Infrastructure

## Found: 8 Core(s) / 16384 MB RAM for Primary Master master.puppetdebug.vlan
## Specify the following in Hiera in nodes/master.puppetdebug.vlan.yaml

---
puppet_enterprise::profile::database::shared_buffers: 4096MB
puppet_enterprise::puppetdb::command_processing_threads: 2
puppet_enterprise::master::jruby_max_active_instances: 6
puppet_enterprise::profile::master::java_args:
  Xms: 4608m
  Xmx: 4608m
puppet_enterprise::profile::puppetdb::java_args:
  Xms: 1638m
  Xmx: 1638m
puppet_enterprise::profile::console::java_args:
  Xms: 512m
  Xmx: 512m
puppet_enterprise::profile::orchestrator::java_args:
  Xms: 768m
  Xmx: 768m
puppet_enterprise::profile::amq::broker::heap_mb: 1024
```

### Parameters

##### `--hiera DIRECTORY`

When specified, settings are redirected to Hiera YAML files in the `hiera` directory.

For example:

```
[root@split-master ~]# puppet infrastructure tune --hiera /tmp/nodes
### Puppet Infrastructure Summary: Found a Split Infrastructure

## Found: 16 Core(s) / 32768 MB RAM for Primary Master split-master.puppetdebug.vlan
## Wrote Hiera YAML to /tmp/nodes/split-master.puppetdebug.vlan.yaml

## Found: 4 Core(s) / 8192 MB RAM for Console Host split-console.puppetdebug.vlan
## Wrote Hiera YAML to /tmp/nodes/split-console.puppetdebug.vlan.yaml

## Found: 8 Core(s) / 16384 MB RAM for PuppetDB Host split-db.puppetdebug.vlan
## Wrote Hiera YAML to /tmp/nodes/split-db.puppetdebug.vlan.yaml
```

##### `--force`

When specified, do not enforce minimum system requirements (4 Cores, 8 GB RAM) for infrastructure hosts, as documented in: https://puppet.com/docs/pe/latest/installing/system_requirements.html

## Limitations

Support limited to the following infrastructures:

* Monolithic
* Monolithic with Compile Masters
* Monolithic with External PostgreSQL
* Monolithic with Compile Masters with External PostgreSQL
* Monolithic with HA
* Monolithic with Compile Masters with HA
* Split
* Split with Compile Masters
* Split with External PostgreSQL
* Split with Compile Masters with External PostgreSQL
