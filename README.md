# pe_tune

#### Table of Contents

1. [Description - What the module does and why it is useful](#description)
1. [Setup - Getting started with this module](#setup)
1. [Usage - Command parameters and how to use them](#usage)
1. [Reference - How the module works and how to use its output](#reference)
1. [Limitations - Supported infrastructures and versions](#limitations)

## Description

> The fault, dear Brutus, is not in our stars, but in our defaults, that we are under-allocating system resources.

The default settings for Puppet Enterprise services are tuned, but not necessarily optimized for PE Infrastructure type and the combination of PE services competing for system resources on each PE Infrastructure host.

This module provides a Puppet command `puppet pe tune` that outputs optimized settings for Puppet Enterprise services based upon available system resources.
This command expects that you have provisioned the PE Infrastructure hosts with the system resources required to handle the workload, given agent count and code and environment complexity.

Puppet Enterprise 2018.1.3 and newer includes this functionality via the `puppet infrastructure tune` command.
To use this command instead of `puppet infrastructure tune` with Puppet Enterprise 2018.1.3 and newer, refer to [Limitations](#limitations).

## Setup

Install this module on the Primary Master.

For example, to install the latest version:

```shell
git clone --depth=1 --branch=master https://github.com/tkishel/pe_tune.git /etc/puppetlabs/code/modules/pe_tune
```

Or to install the latest release:

```shell
wget -q -O - https://api.github.com/repos/tkishel/pe_tune/releases/latest | grep -oP '"tarball_url": "\K(.*)(?=")' | wget -q -i - -O - | tar -xzf - && mv tkishel-pe_tune* /etc/puppetlabs/code/modules/pe_tune
```

## Usage

1. Run the `puppet pe tune` subcommand as root on the Primary Master.
1. Verify the optimized settings.
1. Add the optimized settings to Hiera.
1. Remove any duplicate settings from the Console.
1. Run `puppet agent -t` on each PE Infrastructure host to apply the optimized settings.

#### Parameters

##### `--common`

Extract common settings from node-specific settings when outputting optimized settings.

A common setting is one with a value that is identical on multiple hosts.
This option extracts and outputs common settings separately from node-specific settings, for use in `common.yaml`.

##### `--compare`

Output a comparison of currently-defined and optimized settings.

##### `--current`

Output currently-defined settings, in JSON format.

Settings may be defined either in the Classifier (the Console) or in Hiera, with Classifier settings taking precedence over Hiera settings.
This option also identifies duplicate settings defined in both the Classifier and Hiera.
Best practice is to define settings in Hiera (preferred) or the Classifier, but not both.

##### `--debug`

Enable logging of debug information.

##### `--hiera DIRECTORY`

Output optimized settings to the specified directory, as YAML files for use in Hiera.

> Do not specify a directory in your Hiera hierarchy if that directory is managed by Code Manager. Instead: specify a temporary directory, verify the settings in resulting files, and merge them into the control repository that contains your Hiera data.

##### `--force`

Do not enforce minimum system requirements (4 CPU / 8 GB RAM) for PE Infrastructure hosts.

##### `--inventory FILE`

Use the specified YAML file to define PE Infrastructure hosts.

This eliminates a dependency upon PuppetDB to query facts and classes for PE Infrastructure hosts.
Refer to the [examples](examples) directory of this module for details.

##### `--local`

Use the local system to define a monolithic master host.

This eliminates a dependency upon PuppetDB to query facts and classes for PE Infrastructure hosts, and is only useful after a clean install of a monolithic master host.

##### `--memory_per_jruby MB`

Amount of RAM to allocate for each Puppet Server JRuby.

##### `--memory_reserved_for_os MB`

Amount of RAM to reserve for the operating system and other services.

##### `--node CERTNAME`

Limit output to a single PE Infrastructure host.

##### `--use_current_memory_per_jruby`

Use currently-defined settings to determine `memory_per_jruby`.

## Reference

This command outputs optimized settings for PE services as follows.

1. Query PuppetDB for PE Infrastructure hosts (query for declared PE classes)
1. Identify PE Infrastructure type: Standard, Large, Extra Large (legacy: Split)
1. Query PuppetDB for CPU and RAM facts for each PE Infrastructure host (query for processors, memory)
1. Output settings for PE services for each PE Infrastructure host (as parameters for the declared PE classes)

### Output

By default, settings are output to STDOUT.

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

By default, this command outputs node-specific settings for use in node-specific YAML files in a node-specific Hiera hierarchy.

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

### Infrastructure Support

Support is limited to the following infrastructures:

* Monolithic Master
* Monolithic Master with HA
* Monolithic Master with Compile Masters
* Monolithic Master with Compile Masters with HA
* Monolithic Master with Compile Masters with External PostgreSQL
* Monolithic Master with External PostgreSQL
* Split Infrastructure
* Split Infrastructure with Compile Masters
* Split Infrastructure with Compile Masters with External PostgreSQL
* Split Infrastructure with External PostgreSQL

### Version Support

Support is limited to the following versions:

* PE 2016.4.x (\*)
* PE 2017.3.x (\*)
* PE 2018.x.x
* PE 2019.x.x

\* In these versions, this command is unable to identify PE Database hosts or tune PE PostgreSQL services.

#### Puppet Enterprise 2018.1.3 and Newer

This command is the upstream version of the `puppet infrastructure tune` command built into Puppet Enterprise 2018.1.3 and newer.
Installing this module in Puppet Enterprise 2018.1.3 and newer will result in a conflict with the `puppet infrastructure tune` subcommand.
To avoid that conflict, install this module and run this command outside the `modulepath`.

For example:

```shell
mkdir -p /tmp/puppet_modules
(which git > /dev/null 2>&1 && git clone --depth=1 --branch=master https://github.com/tkishel/pe_tune.git /tmp/puppet_modules/pe_tune) || \
wget -q -O - https://api.github.com/repos/tkishel/pe_tune/releases/latest | grep -oP '"tarball_url": "\K(.*)(?=")' | wget -q -i - -O - | tar -xzf - && mv tkishel-pe_tune* /tmp/puppet_modules/pe_tune
```

```
puppet pe tune --modulepath /tmp/puppet_modules
```

#### Puppet Enterprise 2018.1.2 and Older

This module may not be able to query PuppetDB in older versions of Puppet Enterprise.
To avoid that error, install this module and run the command outside the `modulepath`.

```shell
mkdir -p /tmp/puppet_modules
(which git > /dev/null 2>&1 && git clone --depth=1 --branch=master https://github.com/tkishel/pe_tune.git /tmp/puppet_modules/pe_tune) || \
wget -q -O - https://api.github.com/repos/tkishel/pe_tune/releases/latest | grep -oP '"tarball_url": "\K(.*)(?=")' | wget -q -i - -O - | tar -xzf - && mv tkishel-pe_tune* /tmp/puppet_modules/pe_tune
```

```shell
/tmp/puppet_modules/pe_tune/lib/puppet_x/puppetlabs/tune.rb
```

![AUTOTUNE](autotune.jpeg?raw=true "AUTOTUNE")
