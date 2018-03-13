require 'puppet'

module PuppetX
  module Puppetlabs
    # Read puppet.conf.
    class Configuration
      attr_reader :puppet_conf_server

      def initialize
        read_primary_master
      end

      def read_primary_master
        Puppet.debug("Reading: #{Puppet[:config]}")
        not_primary_master = Puppet[:certname] != Puppet[:server]
        if not_primary_master
          Puppet.err('This command must be run on the Primary Master')
          exit 1
        end
        @puppet_conf_server = Puppet[:server]
        Puppet.debug("Found puppet.conf server: #{@puppet_conf_server}")
      end
    end
  end
end
