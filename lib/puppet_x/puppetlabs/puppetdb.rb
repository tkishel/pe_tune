require 'puppet/util/puppetdb'

module PuppetX
  module Puppetlabs
    # Query PuppetDB via its API.
    class Puppetdb
      attr_reader :environment
      attr_reader :replica_masters
      attr_reader :primary_masters
      attr_reader :compile_masters
      attr_reader :console_hosts
      attr_reader :puppetdb_hosts
      attr_reader :database_hosts

      def initialize
        # PE-15116 results in Puppet[:environment] being set to 'enterprise' within the infrastructure face.
        @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment').chomp
        @replica_masters = get_pe_infra_nodes_by_class('Primary_master_replica', @environment)
        @primary_masters = get_pe_infra_nodes_by_class('Certificate_authority', @environment) - @replica_masters
        @compile_masters = get_pe_infra_nodes_by_class('Master', @environment)   - @primary_masters - @replica_masters
        @console_hosts   = get_pe_infra_nodes_by_class('Console', @environment)  - @primary_masters - @replica_masters
        @puppetdb_hosts  = get_pe_infra_nodes_by_class('Puppetdb', @environment) - @primary_masters - @replica_masters
        @database_hosts  = get_pe_infra_nodes_by_class('Database', @environment) - @primary_masters - @replica_masters
      end

      # Note: These fact methods could be replaced by PuppetX::Puppetlabs::Configuration::read_node_facts()

      def get_cpu_for_node(certname)
        results = get_fact_for_node(certname, 'processors', @environment)
        return 0 unless results
        results['count'].to_i
      end

      def get_ram_for_node(certname)
        results = get_fact_for_node(certname, 'memory', @environment)
        return 0 unless results
        results['system']['total_bytes'].to_i
      end
 
      def get_fact_for_node(certname, fact_name, environment = 'production')
        Puppet.debug("Querying PuppetDB for Fact: #{certname} #{fact_name}")
        pql = ['from', 'facts',
              ['extract', ['name', 'value'],
                ['and',
                  ['=', 'environment', environment],
                  ['=', ['node', 'active'], true],
                  ['=', 'certname', certname],
                  ['=', 'name', fact_name]
                ]
              ]
            ]
        results = Puppet::Util::Puppetdb.query_puppetdb(pql)
        return if results.empty?
        Puppet.debug(results)
        return unless results.first['value']
        results.first['value']
      end

      # Note: Move this method to: 
      # Note: https://github.com/puppetlabs/puppetlabs-pe_manager/blob/irving/lib/puppet/util/pe_conf/recover/puppetdb.rb

      def get_pe_infra_nodes_by_class(class_name, environment = 'production')
        Puppet.debug("Querying PuppetDB for Class: Puppet_enterprise::Profile::#{class_name}")
        pql = ['from', 'resources',
              ['extract', ['certname', 'parameters'],
                ['and',
                  ['=', 'type', 'Class'],
                  ['=', 'environment', environment],
                  ['=', ['node', 'active'], true],
                  ['=', 'title', "Puppet_enterprise::Profile::#{class_name}"]
                ]
              ]
            ]
        results = Puppet::Util::Puppetdb.query_puppetdb(pql)
        Puppet.debug(results)
        results.map { |resource| resource.fetch('certname') }
      end
    end
  end
end
