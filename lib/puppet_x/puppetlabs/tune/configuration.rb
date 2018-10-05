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

        def initialize
          @pe_conf = read_pe_conf
        end

        def read_pe_conf
          pe_conf_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
          Puppet.debug("Reading: #{pe_conf_file}")
          if File.exist?(pe_conf_file)
            Puppet.debug("Found: #{pe_conf_file}")
            pe_conf = Hocon.load(pe_conf_file)
          else
            Puppet.debug("File does not exist: #{pe_conf_file}")
            pe_conf = {}
          end
          pe_conf
        end

        def get_pe_conf_host(role)
          return if @pe_conf.empty?
          host = @pe_conf["puppet_enterprise::#{role}"]
          return if host.nil? || host.empty?
          Puppet.debug("Found pe.conf #{role}: #{host}")
          host = Puppet[:certname] if ['%{trusted.certname}', '%{::trusted.certname}'].include?(host)
          Puppet.debug("Using pe.conf #{role}: #{host}")
          host
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

        def count_active_nodes
          Puppet.debug('Querying PuppetDB for Active Nodes')
          pql = ['from', 'nodes',
                ['and',
                  ['=', ['node', 'active'], true],
                ]
              ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          Puppet.debug(results)
          results.count
        end

        # "name" => "catalog_application",
        # "name" => "config_retrieval",
        # "name" => "convert_catalog",
        # "name" => "fact_generation",
        # "name" => "node_retrieval",
        # "name" => "plugin_sync",
        # "name" => "transaction_evaluation",
        # "name" => "total",

        def get_average_compile_time(query_limit = 1000)
          Puppet.debug('Querying PuppetDB for Average Compile Time')
          pql = ['from', 'reports',
                ['extract',
                  ['hash', 'start_time', 'end_time', 'metrics'],
                ],
                ['limit', query_limit]
              ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          random_report_hash = results.sample['hash']
          Puppet.debug("Random report: #{random_report_hash}")
          # run_times = results.map do |report|
          #   Time.parse(report['end_time']) - Time.parse(report['start_time'])
          # end
          # avg_run_time = (run_times.inject(0.0) { |sum, element| sum + element } / run_times.size).ceil
          # Filter out reports that do not contain metric data.
          results.delete_if { |report| report['metrics']['data'].empty? }
          # Collect config_retrieval time or if absent, total time.
          config_retrieval_times = results.map do |report|
            begin
              report['metrics']['data'].select { |h| (h['name'] == 'config_retrieval' && h['category'] == 'time') }.first.fetch('value')
            rescue NoMethodError
              report['metrics']['data'].select { |h| (h['name'] == 'total' && h['category'] == 'time') }.first.fetch('value')
            end
          end
          avg_config_retrieval_time = config_retrieval_times.reduce(0.0) { |sum, element| sum + element } / config_retrieval_times.size
          avg_config_retrieval_time.ceil
        end

        def get_node_facts(certname, environment)
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

        # Return settings configured in Hiera and the classifier, identifying duplicates and merging the results.

        def get_hiera_classifier_settings(certname, settings, environment, environmentpath)
          duplicates = []
          overrides_hiera, overrides_classifier = get_hiera_classifier_overrides(certname, settings, environment, environmentpath)
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
          { 'params' => overrides, 'duplicates' => duplicates }
        end

        # Internal helper methods.

        private

        def get_hiera_classifier_overrides(certname, settings, environment, _environmentpath)
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
