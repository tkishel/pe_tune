require 'puppet/indirector/face'
require 'puppet/feature/base'

require 'puppet_x/puppetlabs/configuration'
require 'puppet_x/puppetlabs/infrastructure'
require 'puppet_x/puppetlabs/puppetdb'

require 'puppet_x/puppetlabs/tune'

Puppet::Face.define(:infrastructure, '1.0.0') do
  action(:tune) do
    summary 'Inspect infrastructure and output optimized settings for services'

    description <<-'DESC'
      Collects information about your Puppet Enterprise installation.
      Outputs optimized settings for services based upon CPU and RAM.
    DESC

    option '--hiera DIRECTORY' do
      summary 'Optional output directory for settings as Hiera YAML files'
      default_to { nil }
    end

    option '--hocon DIRECTORY' do
      summary 'BETA: Optional output directory for settings as HOCON files'
      default_to { nil }
    end

    option '--force' do
      summary 'Do not enforce minimum system requirements'
      default_to { false }
    end

    when_invoked do |*args|
      options = args.pop

      Puppet.debug("Command Options: #{options}")

      Tune = PuppetX::Puppetlabs::Tune.new(options)
      Tune.output_optimized_settings

      return
    end
  end
end
