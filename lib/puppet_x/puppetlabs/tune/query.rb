require 'puppet/util/pe_conf'
require 'puppet/util/pe_conf/recover'

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current, or calculate optimized settings.
    class Tune
      # Interface to Puppet::Util::Puppetdb, Puppet::Util::Pe_conf, and Puppet::Util::Pe_conf::Recover
      class Query
        attr_reader :environment
        attr_reader :environmentpath

        def initialize
          @environment = 'production'
          @environmentpath = '/etc/puppetlabs/code/environments'
        end

        # PE-15116 overrides 'environment' and 'environmentpath' in the 'puppet infrastructure' face.
        # The original values are required by methods in this class.

        def pe_environment(certname)
          environment = catalog_environment(certname)
          if environment
            @environment = environment
          else
            Puppet.debug("No Environment found in PuppetDB using: #{certname}")
            Puppet.debug("Querying 'puppet config print environment' for Environment")
            @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master', 'combine' => false).chomp
          end
          @environmentpath = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environmentpath --section master', 'combine' => false).chomp
        end

        # Query PuppetDB for the environment of a PE Infrastructure node.

        def catalog_environment(certname)
          Puppet.debug("Querying PuppetDB for Environment using: #{certname}")
          pql = ['from', 'nodes',
                ['extract', ['certname', 'catalog_environment'],
                  ['and',
                    ['=', 'certname', certname],
                  ]
                ]
              ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
            return nil
          end
          Puppet.debug('Begin Query Results')
          Puppet.debug(results)
          Puppet.debug('End Query Results')
          results[0]['catalog_environment']
        end

        # Query PuppetDB for the count of active nodes.

        def active_node_count
          Puppet.debug('Querying PuppetDB for Active Nodes')
          pql = ['from', 'nodes',
                ['extract', ['certname'],
                  ['and',
                    ['=', ['node', 'active'], true],
                  ]
                ]
              ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
          end
          Puppet.debug('Begin Query Results')
          Puppet.debug(results)
          Puppet.debug('End Query Results')
          results.count
        end

        # Query PuppetDB for config_retrieval or total time metrics.

        # "name" => "catalog_application",
        # "name" => "config_retrieval",
        # "name" => "convert_catalog",
        # "name" => "fact_generation",
        # "name" => "node_retrieval",
        # "name" => "plugin_sync",
        # "name" => "transaction_evaluation",
        # "name" => "total",

        def average_compile_time(query_limit = 1000)
          Puppet.debug('Querying PuppetDB for Average Compile Time')
          pql = ['from', 'reports',
                ['extract',
                  ['hash', 'start_time', 'end_time', 'metrics'],
                ],
                ['limit', query_limit]
              ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
            return nil
          end
          random_report_hash = results.sample['hash']
          Puppet.debug("Random report: #{random_report_hash}")
          average_metric_time(results, 'config_retrieval', 'total')
        end

        # Query PuppetDB for average config_retrieval or time metrics for a given time range.
        #
        # @param [String] start_time  Value of start_time to query data for
        # @param [String] end_time  Value of end_time to query data for
        #
        # @return [Integer]  Average time for config_retrieval or total time in data set

        def average_compile_time_for_range(start_time, end_time)
          start_time = Time.parse(start_time)
          end_time = Time.parse(end_time)
          # Ensure that start is less than end
          start_time, end_time = [start_time, end_time].sort

          # Ensure that time zone is not emitted in string sent to pdb endpoint
          start_time = start_time.strftime "%Y-%m-%d %H:%M:%S"
          end_time = end_time.strftime "%Y-%m-%d %H:%M:%S"

          # Extract metrics from reports that only fall within the time fence
          Puppet.debug('Querying PuppetDB for Average Compile Time for Range')
          pql = ['from', 'reports',
                  ['extract', 'metrics',
                    ['and',
                      ['>', 'start_time', start_time],
                      ['<', 'end_time', end_time]
                    ]
                  ]
                ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
            return nil
          end
          average_metric_time(results, 'config_retrieval', 'total')
        end

        # Calculate average time for PuppetDB metric on a given data set.
        #
        # @param [Array<Hash>] data  Results from call to query_puppetdb(pql)
        # @param [String] metric  Primary metric to find and average time values for
        # @param [String] failover_metric  Secondary metric to use if primary is not found
        #
        # @return [Integer]  Average time for metric in data set

        def average_metric_time(data, metric, failover_metric)
          result = nil
          begin
            data.delete_if { |report| report['metrics']['data'].empty? }
            config_retrieval_times = data.map do |report|
              report['metrics']['data'].select { |md|
                md['category'] == 'time' && (md['name'] == metric || md['name'] == failover_metric)
              }.first.fetch('value')
            end
            avg_config_retrieval_time = config_retrieval_times.reduce(0.0, :+) / config_retrieval_times.size
            result = avg_config_retrieval_time.ceil
          rescue # rubocop:disable Lint/HandleExceptions
          end
          result
        end

        # Query PuppetDB for nodes with a PE Infrastructure class.

        def infra_nodes_with_class(classname)
          Puppet.debug("Querying PuppetDB for Class: Puppet_enterprise::Profile::#{classname}")
          pql = ['from', 'resources',
                ['extract', ['certname', 'parameters'],
                  ['and',
                    ['=', 'type', 'Class'],
                    ['=', 'environment', @environment],
                    ['=', 'title', "Puppet_enterprise::Profile::#{classname}"],
                    ['=', ['node', 'active'], true],
                  ]
                ]
              ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
          end
          Puppet.debug('Begin Query Results')
          Puppet.debug(results)
          Puppet.debug('End Query Results')
          results.map { |resource| resource.fetch('certname') }
        end

        # Query PuppetDB for facts for a node.

        def node_facts(certname)
          Puppet.debug("Querying PuppetDB for Facts for: #{certname}")
          pql = ['from', 'facts',
                ['extract', ['name', 'value'],
                  ['and',
                    ['=', 'certname', certname],
                    ['=', 'environment', @environment],
                  ]
                ]
              ]
          results = query_puppetdb(pql)
          if results.nil?
            Puppet.debug('No result for PuppetDB Query')
            return nil
          end
          if results.empty?
            Puppet.debug('No results for PuppetDB Query')
          end
          Puppet.debug('Begin Query Results')
          Puppet.debug(results)
          Puppet.debug('End Query Results')
          facts = {}
          results.each do |fact, _nil|
            facts[fact['name']] = fact['value']
          end
          facts
        end

        # Return settings configured in Hiera and the Classifier, identifying duplicates and merging the results.

        def hiera_classifier_settings(certname, settings)
          duplicates = []
          overrides_hiera, overrides_classifier = hiera_classifier_overrides(certname, settings)
          Puppet.debug("Settings from Hiera for: #{certname}: #{overrides_hiera}")
          Puppet.debug("Settings from Classifier for: #{certname}: #{overrides_classifier}")
          overrides = overrides_hiera
          overrides_classifier.each do |classifier_k, classifier_v|
            next unless settings.include?(classifier_k)
            if overrides.key?(classifier_k)
              duplicates.push("#{classifier_k} ... Hiera: #{overrides_hiera[classifier_k]} ... Classifier: #{classifier_v} ")
            end
            # Classifer settings take precedence over Hiera settings.
            # Hiera settings include pe.conf.
            overrides[classifier_k] = classifier_v
          end
          return { 'params' => overrides, 'duplicates' => duplicates }
        rescue Puppet::Error
          return nil
        end

        # Internal helper methods.

        private

        # If 'puppet/util/puppetdb' would be required at the top of the file,
        # then it would be autoloaded/required as part of the install process,
        # resulting in an error.

        def query_puppetdb(pql)
          require 'puppet/util/puppetdb'
          return Puppet::Util::Puppetdb.query_puppetdb(pql)
        rescue Puppet::Error
          return nil
        end

        # Extract the beating heart of a puppet compiler for lookup purposes.

        def hiera_classifier_overrides(certname, settings)
          if recover_with_instance_method?
            recover = Puppet::Util::Pe_conf::Recover.new
            recover_node_facts = recover.facts_for_node(certname, @environment)
            node_terminus = recover.get_node_terminus
            overrides_hiera = recover.find_hiera_overrides(certname, settings, recover_node_facts, @environment, node_terminus)
            overrides_classifier = recover.classifier_overrides_for_node(certname, recover_node_facts, recover_node_facts['::trusted'])
          else
            recover_node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
            if recover_with_node_terminus_method?
              node_terminus = Puppet::Util::Pe_conf::Recover.get_node_terminus
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(certname, settings, recover_node_facts, @environment, node_terminus)
            else
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(settings, recover_node_facts, @environment)
            end
            overrides_classifier = Puppet::Util::Pe_conf::Recover.classifier_overrides_for_node(certname, recover_node_facts, recover_node_facts['::trusted'])
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
