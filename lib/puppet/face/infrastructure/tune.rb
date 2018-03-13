require 'puppet/indirector/face'
require 'puppet/feature/base'

require 'puppet_x/puppetlabs/configuration'
require 'puppet_x/puppetlabs/puppetdb'
require 'puppet_x/puppetlabs/tune'

Puppet::Face.define(:infrastructure, '1.0.0') do
  action(:tune) do
    summary 'Inspect infrastructure and output optimized settings for services'

    description <<-'DESC'
      Collects information about your Puppet Enterprise installation.
      Outputs optimized settings for services based upon CPU and RAM.
    DESC

    option '--current' do
      summary 'Output current settings and exit'
      default_to { false }
    end

    option '--deduplicate' do
      summary 'Extract common settings from node-specific settings'
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
