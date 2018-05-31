require 'hocon'
require 'puppet/util/pe_conf'
require 'puppet/util/pe_conf/recover'

module PuppetX
  module Puppetlabs
    # Interface to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover
    class Tune::Pe_conf
      attr_reader :environment
      attr_reader :pe_conf
      attr_reader :pe_conf_database_host

      def initialize
        # PE-15116 results in Puppet[:environment] being set to 'enterprise' in the infrastructure face.
        @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
        @pe_conf = read_pe_conf
        pe_conf_puppet_master_host = @pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
        pe_conf_puppet_master_host = Puppet[:certname] if pe_conf_puppet_master_host == '%{::trusted.certname}'
        Puppet.debug("Found pe.conf puppet_master_host: #{pe_conf_puppet_master_host}")
        pe_conf_puppetdb_host = @pe_conf['puppet_enterprise::puppetdb_host'] || pe_conf_puppet_master_host
        Puppet.debug("Found pe.conf pe_puppetdb_host: #{pe_conf_puppetdb_host}")
        @pe_conf_database_host = @pe_conf['puppet_enterprise::database_host'] || pe_conf_puppetdb_host
        Puppet.debug("Found pe.conf pe_database_host: #{@pe_conf_database_host}")
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
        pe_conf
      end

      def read_node_facts(certname)
        node_facts = {}
        if recover_without_instance?
          facts_hash = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
          if facts_hash.key?('puppetversion')
            node_facts = facts_hash
          else
            # Prior to PE-22444, facts are returned as a Hash with elements in this format: {"name"=>"puppetversion", "value"=>"4.10.10"} => nil
            facts_hash.each do |fact, _nil|
              node_facts[fact['name']] = fact['value']
            end
          end
        else
          recover = Puppet::Util::Pe_conf::Recover.new
          node_facts = recover.facts_for_node(certname, @environment)
        end
        node_facts
      end

      def read_hiera_classifier_overrides(certname, settings)
        if recover_without_instance?
          node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
          if recover_with_node_terminus?
            node_terminus = Puppet::Util::Pe_conf::Recover.get_node_terminus
            overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
          else
            overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(settings, node_facts, @environment)
          end
          overrides_classifier = Puppet::Util::Pe_conf::Recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
        else
          recover = Puppet::Util::Pe_conf::Recover.new
          node_facts = recover.facts_for_node(certname, @environment)
          node_terminus = recover.get_node_terminus
          overrides_hiera = recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
          overrides_classifier = recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
        end
        overrides = overrides_hiera
        duplicates = []
        # Classifer settings take precedence over Hiera settings.
        overrides_classifier.each do |k, v|
          # find_hiera_overrides() returns the specified settings, while classifier_overrides_for_node() returns all settings.
          next unless settings.include?(k)
          # This setting is specifed in both the Classifer and Hiera.
          if overrides.key?(k)
            Puppet.debug("# Duplicate settings for #{certname}: #{k} Classifier: #{v} Hiera: #{overrides_hiera[k]}")
            duplicates.push(k)
          end
          overrides[k] = v
        end
        [overrides, duplicates]
      end

      # Internal helper methods.

      private

      # PE-24106 changes Recover to a class with instance methods.

      def recover_without_instance?
        defined?(Puppet::Util::Pe_conf::Recover.facts_for_node) == 'method'
      end

      # In some versions, Puppet::Util::Pe_conf::Recover does not implement get_node_terminus() and implements find_hiera_overrides(params, facts, environment)

      def recover_with_node_terminus?
        defined?(Puppet::Util::Pe_conf::Recover.get_node_terminus) == 'method'
      end
    end
  end
end
