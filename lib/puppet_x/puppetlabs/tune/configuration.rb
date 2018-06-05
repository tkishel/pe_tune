require 'hocon'
require 'puppet/util/pe_conf'
require 'puppet/util/pe_conf/recover'
require 'puppet/util/puppetdb'

module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Interface to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover
      class Configuration
        attr_reader :pe_conf
        attr_reader :pe_conf_database_host

        def initialize
          @pe_conf = read_pe_conf
          @pe_conf_database_host = identify_pe_conf_database_host(@pe_conf)
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

        def identify_pe_conf_database_host(pe_conf)
          return Puppet[:certname] if pe_conf.empty?
          pe_conf_puppet_master_host = pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
          pe_conf_puppet_master_host = Puppet[:certname] if pe_conf_puppet_master_host == '%{::trusted.certname}'
          Puppet.debug("Found pe.conf puppet_master_host: #{pe_conf_puppet_master_host}")
          pe_conf_puppetdb_host = pe_conf['puppet_enterprise::puppetdb_host'] || pe_conf_puppet_master_host
          Puppet.debug("Found pe.conf pe_puppetdb_host: #{pe_conf_puppetdb_host}")
          pe_conf_database_host = pe_conf['puppet_enterprise::database_host'] || pe_conf_puppetdb_host
          Puppet.debug("Found pe.conf pe_database_host: #{pe_conf_database_host}")
          pe_conf_database_host
        end

        def get_infra_nodes_with_class(classname, environment)
          Puppet.debug("Querying PuppetDB for Class: Puppet_enterprise::Profile::#{classname}")
          pql = ['from', 'resources',
                ['extract', ['certname', 'parameters'],
                  ['and',
                    ['=', 'type', 'Class'],
                    ['=', 'environment', environment],
                    ['=', ['node', 'active'], true],
                    ['=', 'title', "Puppet_enterprise::Profile::#{classname}"]
                  ]
                ]
              ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          Puppet.debug(results)
          results.map { |resource| resource.fetch('certname') }
        end

        def read_node_facts(certname, environment)
          node_facts = {}
          if recover_with_instance_method?
            recover = Puppet::Util::Pe_conf::Recover.new
            node_facts = recover.facts_for_node(certname, environment)
          else
            facts_hash = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, environment)
            if facts_hash.key?('puppetversion')
              node_facts = facts_hash
            else
              # Prior to PE-22444, facts are returned as a Hash with elements in this format: {"name"=>"puppetversion", "value"=>"4.10.10"} => nil
              facts_hash.each do |fact, _nil|
                node_facts[fact['name']] = fact['value']
              end
            end
          end
          node_facts
        end

        def read_hiera_classifier_overrides(certname, settings, environment, environmentpath)
          duplicates = []
          overrides_hiera, overrides_classifier = _read_hiera_classifier_overrides(certname, settings, environment, environmentpath)
          overrides = overrides_hiera
          overrides_classifier.each do |classifier_k, classifier_v|
            next unless settings.include?(classifier_k)
            if overrides.key?(classifier_k)
              Puppet.debug("# Duplicate settings for #{certname}: #{classifier_k} Classifier: #{classifier_v} Hiera: #{overrides_hiera[classifier_k]}")
              duplicates.push(classifier_k)
            end
            # Classifer settings take precedence over Hiera settings.
            overrides[classifier_k] = classifier_v
          end
          [overrides, duplicates]
        end

        def _read_hiera_classifier_overrides(certname, settings, environment, _environmentpath)
          if recover_with_instance_method?
            recover = Puppet::Util::Pe_conf::Recover.new
            node_facts = recover.facts_for_node(certname, environment)
            node_terminus = recover.get_node_terminus
            overrides_hiera = recover.find_hiera_overrides(certname, settings, node_facts, environment, node_terminus)
            overrides_classifier = recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
          else
            node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, environment)
            if recover_with_node_terminus_method?
              node_terminus = Puppet::Util::Pe_conf::Recover.get_node_terminus
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(certname, settings, node_facts, environment, node_terminus)
            else
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(settings, node_facts, environment)
            end
            overrides_classifier = Puppet::Util::Pe_conf::Recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
          end
          [overrides_hiera, overrides_classifier]
        end

        # Internal helper methods.

        private

        # PE-24106 changes Recover to a class with instance methods.

        def recover_with_instance_method?
          defined?(Puppet::Util::Pe_conf::Recover.facts_for_node) != 'method'
        end

        # In some versions, Puppet::Util::Pe_conf::Recover does not implement get_node_terminus() and implements find_hiera_overrides(params, facts, environment)

        def recover_with_node_terminus_method?
          defined?(Puppet::Util::Pe_conf::Recover.get_node_terminus) == 'method'
        end
      end
    end
  end
end
