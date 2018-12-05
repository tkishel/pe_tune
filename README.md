# pe_tune

#### Table of Contents

1. [Description - What the module does and why it is useful](#description)
1. [Setup - Getting started with this module](#setup)
1. [Usage - Command parameters and how to use it](#usage)
1. [Reference - How the module works and how to use its output](#reference)
1. [Limitations - Supported versions and infrastructures](#limitations)

## Description

> The fault, dear Brutus, is not in our stars, but in our defaults, that we are under-allocated.

This module provides a Puppet subcommand that outputs optimized settings for Puppet Enterprise services based upon available hardware resources.

## Setup

Install this module on the Primary Master.

For example:

```shell
git clone https://github.com/tkishel/pe_tune.git /etc/puppetlabs/code/modules/pe_tune
```

## Usage

1. Run the `puppet pe tune` command as root on the Primary Master.
1. Verify the optimized settings.
1. Add the optimized settings to Hiera.
1. Remove any duplicate settings from the Console.
1. Run `puppet agent -t` on each Puppet Enterprise infrastructure node to apply the optimized settings.

#### Parameters

##### `--common`

Extract common settings from node-specific settings.

A common setting is one with a value that is not unique to a specific node.

##### `--current`

Output currently defined settings, in JSON format, and exit.

Settings may be defined either in the Classifier (the Console) or in Hiera, with Classifier settings taking precedence over Hiera settings. This option also identifies duplicate settings found in both the Classifier and Hiera. Best practice is to define settings in Hiera (preferred) or the Classifier, but not both.

##### `--debug`

Enable logging of debug information.

##### `--hiera DIRECTORY`

Output optimized settings to the specified directory, as YAML files, for use in Hiera.

Note: Do not specify a directory in your Hiera hierarchy, which should be managed by Code Manager. Instead: specify a temporary directory, verify the settings in resulting files, and merge them into the control repository that contains your Hiera hierarchy.

##### `--force`

Do not enforce minimum system requirements (4 CPU / 8 GB RAM) for infrastructure nodes.

##### `--inventory FILE`

Use the specified YAML file to define infrastructure nodes.

This eliminates a dependency upon PuppetDB to query node facts and classes.

Refer to the examples directory of this module for details.

##### `--local`

Use the local system to define a monolithic master infrastructure node.

This eliminates a dependency upon PuppetDB to query node facts and classes.

##### `--memory_per_jruby MB`

Amount of RAM to allocate for each JRuby.

##### `--memory_reserved_for_os MB`

Amount of RAM to reserve for the OS.

## Reference

This module queries PuppetDB for node group membership to identify PE Infrastructure nodes, queries PuppetDB for processor and memory facts for each PE Infrastructure node, and outputs optimized settings in YAML format use in Hiera.

### Output

By default, optimized settings are output to STDOUT.

For example:

```shell
[root@pe-master ~] puppet pe tune
# Puppet Infrastructure Summary: Found a Monolithic Infrastructure

# Found 8 CPU(s) / 16384 MB RAM for Primary Master pe-master.puppetdebug.vlan
# Specify the following optimized settings in Hiera in nodes/pe-master.puppetdebug.vlan.yaml

---
puppet_enterprise::profile::database::shared_buffers: 4096MB
puppet_enterprise::puppetdb::command_processing_threads: 2
puppet_enterprise::master::puppetserver::jruby_max_active_instances: 5
puppet_enterprise::master::puppetserver::reserved_code_cache: 1024m
puppet_enterprise::profile::master::java_args:
  Xms: 3840m
  Xmx: 3840m
puppet_enterprise::profile::puppetdb::java_args:
  Xms: 1638m
  Xmx: 1638m
puppet_enterprise::profile::console::java_args:
  Xms: 768m
  Xmx: 768m
puppet_enterprise::profile::orchestrator::java_args:
  Xms: 768m
  Xmx: 768m

# CPU Summary: Total/Used/Free: 8/7/1 for pe-master.puppetdebug.vlan
# RAM Summary: Total/Used/Free: 16384/12134/4250 for pe-master.puppetdebug.vlan
# JVM Summary: Using 768 MB per Puppet Server JRuby for pe-master.puppetdebug.vlan
```

This outputs node-specific settings by default. That output needs to be saved to node-specific YAML files in a node-specific hierarchy.

For example:

#### Hiera 3.x

```yaml
---
:hierarchy:
  - "nodes/%{trusted.certname}"
  - "common"
```

#### Hiera 5.x

```yaml
---
version: 5
hierarchy:
  - name: "Per-Node Data"
    path: "nodes/%{trusted.certname}.yaml"
  - name: "Common values"
    path: "common.yaml"
```

### Reference Links:

For more information, review:

* [PE Hardware Requirements](https://puppet.com/docs/pe/latest/installing/hardware_requirements.html)
* [PE Configuration](https://puppet.com/docs/pe/latest/configuring/config_intro.html)
* [PE Java Arguments](https://puppet.com/docs/pe/latest/configuring/config_java_args.html)
* [PE Puppetserver Configuration](https://puppet.com/docs/pe/latest/configuring/config_puppetserver.html)
* [PE Console Configuration](https://puppet.com/docs/pe/latest/configuring/config_console.html)
* [PE PuppetDB Configuration](https://puppet.com/docs/pe/latest/configuring/config_puppetdb.html)
* [PE Tuning Monolithic](https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html)
* [PE Puppetserver Tuning Guide](https://puppet.com/docs/puppetserver/latest/tuning_guide.html)
* [Hiera](https://puppet.com/docs/puppet/latest/hiera_intro.html)

## Limitations

Support is limited to the following versions:

* PE 2016.4.x (\*)
* PE 2017.3.x (\*)
* PE 2018.x.x
* PE 2019.x.x

\* Unable to identify Database Hosts or tune PostgreSQL services in these versions.

Support is limited to the following infrastructures:

* Monolithic Infrastructure
* Monolithic with Compile Masters
* Monolithic with External PostgreSQL
* Monolithic with Compile Masters with External PostgreSQL
* Monolithic with HA
* Monolithic with Compile Masters with HA
* Split Infrastructure
* Split with Compile Masters
* Split with External PostgreSQL
* Split with Compile Masters with External PostgreSQL
