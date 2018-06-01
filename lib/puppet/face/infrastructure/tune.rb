require 'puppet/indirector/face'

require 'puppet_x/puppetlabs/tune'
require 'puppet_x/puppetlabs/tune/calculate'
require 'puppet_x/puppetlabs/tune/pe_conf'
require 'puppet_x/puppetlabs/tune/puppetdb'

Puppet::Face.define(:infrastructure, '1.0.0') do
  action(:tune) do
    summary 'Inspect infrastructure and output optimized settings'

    description <<-'DESC'
      Collects information about your Puppet Enterprise installation.
      Outputs optimized settings for services based upon CPU and RAM.
    DESC

    option '--common' do
      summary 'Extract common settings from node-specific settings'
      default_to { false }
    end

    option '--current' do
      summary 'Output current settings and exit'
      default_to { false }
    end

    option '--force' do
      summary 'Do not enforce minimum system requirements'
      default_to { false }
    end

    option '--hiera DIRECTORY' do
      summary 'Output Hiera YAML files to the specified directory'
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
