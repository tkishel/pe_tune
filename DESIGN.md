# pe_tune

## Problems

The default settings for Puppet Enterprise services are initially tuned, but not necessarily optimized based upon infrastructure type and infrastructure host resources (processors and memory).

There is no command to retune the settings for Puppet Enterprise services after adding infrastructure hosts (compile masters) or increasing the resources (memory and/or processors) of infrastructure hosts.

Tuning Puppet Enterprise services requires synthesizing multiple documents, identifying the resources of each infrastructure host, and performing manual calculations for each infrastructure host and its services.

The tuning documentation for Monolithic infrastructures is limited to a fixed set of resource sizes (4 CPU/8GB RAM, 8 CPU/16GB RAM, 16 CPU/32GB RAM) and therefore is not optimized for other combinations of resources.

## Solutions: Done

* Provide a command to output optimized settings for Puppet Enterprise services, based upon infrastructure type and infrastructure host resources.

## Solutions: To Do

* Define canonical functions (in this module, or in other puppetlabs-pe_* modules) for use by other modules to calculate optimized settings for Puppet Enterprise services.

* Utilize canonical functions in other puppetlabs-pe_* modules to read configuration files, node group membership, and/or profile class assignment.

* Update, normalize, and simplify the existing tuning documentation.

## Reference

### Tuning Documentation:

* https://puppet.com/docs/pe/latest/configuring/config_intro.html
* https://puppet.com/docs/pe/latest/configuring/config_java_args.html
* https://puppet.com/docs/pe/latest/configuring/config_puppetserver.html
* https://puppet.com/docs/pe/latest/configuring/config_console.html
* https://puppet.com/docs/pe/latest/configuring/config_puppetdb.html
* https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
* https://puppet.com/docs/pe/latest/installing/hardware_requirements.html
* https://puppet.com/docs/puppetserver/latest/tuning_guide.html

### Puppet Enterprise Modules:

* puppetlabs-pe_infrastructure
* puppetlabs-pe_install
* puppetlabs-pe_manager
* puppetlabs-puppet_enterprise
