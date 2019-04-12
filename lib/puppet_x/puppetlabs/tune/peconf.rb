module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Interface to PuppetX::Puppetlabs::Meep
      class PEConf
        attr_reader :file

        def initialize(meep_config_path)
          @file = "#{meep_config_path}/conf.d/pe.conf"
          require 'puppet_x/puppetlabs/meep/config'
          # An error is raised if the file does not exist. Create?
          @meep_meep = PuppetX::Puppetlabs::Meep::Modify.new(meep_config_path)
        end

        def write(settings)
          # For now, do not merge existing and optimized settings.
          settings.each do |key, _optimized|
            previous = @meep_meep::get_in_pe_conf(key)
            if previous
              Puppet.debug("Existing value found in pe.conf for #{key}: #{previous}")
              return false
            end
          end

          settings.each do |key, optimized|
            previous = @meep_meep::get_in_pe_conf(key)
            Puppet.debug("Previous value in pe.conf for #{key}: #{previous}")
            if previous.is_a?(Hash)
              merged = previous.merge(optimized)
              @meep_meep::set_in_pe_conf(key, merged)
            else
              @meep_meep::set_in_pe_conf(key, optimized)
            end
            updated = @meep_meep::get_in_pe_conf(key)
            Puppet.debug("Updated value in pe.conf for  #{key}: #{updated}")
          end
          true
        end
      end
    end
  end
end
