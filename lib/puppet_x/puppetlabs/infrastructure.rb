require 'hocon'

require 'puppet/util/pe_conf'

module PuppetX
  module Puppetlabs
    # Read pe.conf.
    class Infrastructure
      attr_reader :pe_conf
      attr_reader :pe_conf_puppet_master_host
      attr_reader :pe_conf_puppetdb_host
      attr_reader :pe_conf_database_host

      def initialize
        read_pe_conf
      end

      def read_pe_conf
        pe_conf_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
        Puppet.debug("Reading: #{pe_conf_file}")
        if File.exist?(pe_conf_file)
          Puppet.debug("Found: #{pe_conf_file}")
          @pe_conf = Hocon.load(pe_conf_file)
        else
          Puppet.err("File does not exist: #{pe_conf_file}")
          @pe_conf = {}
        end
        @pe_conf_puppet_master_host = @pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
        @pe_conf_puppet_master_host = Puppet[:certname] if @pe_conf_puppet_master_host == '%{::trusted.certname}'
        @pe_conf_puppetdb_host = @pe_conf['puppet_enterprise::puppetdb_host'] || @pe_conf_puppet_master_host
        @pe_conf_database_host = @pe_conf['puppet_enterprise::database_host'] || @pe_conf_puppetdb_host
        Puppet.debug("Found pe.conf puppet_master_host: #{@pe_conf_puppet_master_host}")
        Puppet.debug("Found pe.conf pe_puppetdb_host: #{@pe_conf_puppetdb_host}")
        Puppet.debug("Found pe.conf pe_database_host: #{@pe_conf_database_host}")
      end

      def write_pe_conf(directory, settings)
        return unless directory
        return if settings.empty?
        pe_conf = Puppet::Util::Pe_conf.new
        pe_conf.recover
        # TODO: Research whether merge! is appropriate or necessary.
        pe_conf.nodes_conf.merge!(settings)
        pe_conf.save(directory)
      end
    end
  end
end
