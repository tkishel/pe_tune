module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Interface to PuppetX::Puppetlabs::Meep
      class Conf
        def initialize(meep_config_path)
          require 'puppet_x/puppetlabs/meep/config'
          @meep_meep = PuppetX::Puppetlabs::Meep::Modify.new(meep_config_path)
        end

        def write(settings)
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
        end
      end
    end
  end
end
