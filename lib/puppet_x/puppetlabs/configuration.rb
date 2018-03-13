require 'hocon'
require 'puppet/util/pe_conf'
require 'puppet/util/pe_conf/recover'

module PuppetX
  module Puppetlabs
    # Query the configuration.
    class Configuration
      attr_reader :environment
      attr_reader :pe_conf_puppet_master_host
      attr_reader :pe_conf_puppetdb_host
      attr_reader :pe_conf_database_host

      def initialize
        # PE-15116 results in Puppet[:environment] == 'enterprise' in the infrastructure face.
        @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
        read_pe_conf
      end

      def read_pe_conf
        pe_conf_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
        Puppet.debug("Reading: #{pe_conf_file}")
        if File.exist?(pe_conf_file)
          Puppet.debug("Found: #{pe_conf_file}")
          pe_conf = Hocon.load(pe_conf_file)
        else
          Puppet.err("File does not exist: #{pe_conf_file}")
          pe_conf = {}
        end
        @pe_conf_puppet_master_host = pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
        @pe_conf_puppet_master_host = Puppet[:certname] if @pe_conf_puppet_master_host == '%{::trusted.certname}'
        @pe_conf_puppetdb_host = pe_conf['puppet_enterprise::puppetdb_host'] || @pe_conf_puppet_master_host
        @pe_conf_database_host = pe_conf['puppet_enterprise::database_host'] || @pe_conf_puppetdb_host
        Puppet.debug("Found pe.conf puppet_master_host: #{@pe_conf_puppet_master_host}")
        Puppet.debug("Found pe.conf pe_puppetdb_host: #{@pe_conf_puppetdb_host}")
        Puppet.debug("Found pe.conf pe_database_host: #{@pe_conf_database_host}")
      end

      # Note: find_hiera_overrides() returns the specified settings, while classifier_overrides_for_node() returns all settings.

      def read_hiera_classifier_overrides(certname, settings)
        # (PE-24106) Change Recover to a Class
        if defined?(Puppet::Util::Pe_conf::Recover.facts_for_node) == 'method'
          # PE 2017
          node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
          node_terminus = Puppet::Util::Pe_conf::Recover.get_node_terminus
          overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
          overrides_classifier = Puppet::Util::Pe_conf::Recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
        else
          # PE 2018
          recover = Puppet::Util::Pe_conf::Recover.new
          node_facts = recover.facts_for_node(certname, @environment)
          node_terminus = recover.get_node_terminus
          overrides_hiera = recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
          overrides_classifier = recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
        end
        overrides = overrides_hiera
        duplicates = []
        # Note: Classifer settings take precedence over Hiera settings.
        overrides_classifier.each do |k, v|
          next unless settings.include?(k)
          # Setting is specifed in both the Classifer and Hiera.
          if overrides.key?(k)
            Puppet.debug("# Duplicate settings for #{certname}: #{k} Classifier: #{v} Hiera: #{overrides_hiera[k]}")
            duplicates.push(k)
          end
          overrides[k] = v
        end
        [overrides, duplicates]
      end

      def read_node_facts(certname)
        node_facts = {}
        # (PE-24106) Change Recover to a Class
        if defined?(Puppet::Util::Pe_conf::Recover.facts_for_node) == 'method'
          # PE 2017
          node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
        else
          # PE 2018
          recover = Puppet::Util::Pe_conf::Recover.new
          node_facts = recover.facts_for_node(certname, @environment)
        end
        node_facts
      end
    end
  end
end
