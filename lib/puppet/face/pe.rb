require 'puppet/indirector/face'

# Load puppet enterprise modules.
# Note that the location of enterprise modules varies from version to version.

enterprise_modules = ['pe_infrastructure', 'pe_install', 'pe_manager']
env_mod = '/opt/puppetlabs/server/data/environments/enterprise/modules'
ent_mod = '/opt/puppetlabs/server/data/enterprise/modules'
enterprise_module_paths = [env_mod, ent_mod]
enterprise_module_paths.each do |enterprise_module_path|
  next unless File.directory?(enterprise_module_path)
  enterprise_modules.each do |enterprise_module|
    enterprise_module_lib = "#{enterprise_module_path}/#{enterprise_module}/lib"
    next if $LOAD_PATH.include?(enterprise_module_lib)
    Puppet.debug("Adding #{enterprise_module} to LOAD_PATH: #{enterprise_module_lib}")
    $LOAD_PATH.unshift(enterprise_module_lib)
  end
end

# Load this module's classes (instead of those in pe_manager).

require_relative '../../puppet_x/puppetlabs/tune'
require_relative '../../puppet_x/puppetlabs/tune/calculate'
require_relative '../../puppet_x/puppetlabs/tune/inventory'
require_relative '../../puppet_x/puppetlabs/tune/query'

Puppet::Face.define(:pe, '1.0.0') do
  summary _('Inspect infrastructure and output settings')
  description <<-'DESC'
    Collects information about your Puppet Enterprise installation.
    Outputs current or optimized settings that tune Puppet Enterprise services.
  DESC

  action(:tune) do
    summary _('Inspect infrastructure and output settings')
    description <<-'DESC'
      Collects information about your Puppet Enterprise installation.
      Outputs current or optimized settings that tune Puppet Enterprise services.
    DESC

    option '--common' do
      summary _('Extract common settings from node settings')
      default_to { false }
    end

    option '--current' do
      summary _('Output currently defined settings, and exit')
      default_to { false }
    end

    option '--estimate' do
      summary _('Output an estimated capacity summary')
      default_to { false }
    end

    option '--force' do
      summary _('Do not enforce minimum system requirements')
      default_to { false }
    end

    option '--hiera DIRECTORY' do
      summary _('Output Hiera YAML files to a directory')
      default_to { nil }
    end

    option '--inventory FILE' do
      summary _('Use a YAML file to define nodes')
      default_to { nil }
    end

    option '--local' do
      summary _('Use the local system to define a node')
      default_to { false }
    end

    option '--memory_per_jruby MB' do
      summary _('Amount of RAM to allocate for each JRuby')
      default_to { nil }
    end

    option '--memory_reserved_for_os MB' do
      summary _('Amount of RAM to reserve for the OS')
      default_to { nil }
    end

    when_invoked do |*args|
      options = args.pop
      Puppet.debug("Command Options: #{options}")
      Tune = PuppetX::Puppetlabs::Tune.new(options)
      if options[:current]
        Tune.output_current_settings
      else
        Tune.output_optimized_settings
      end
      return
    end
  end
end
