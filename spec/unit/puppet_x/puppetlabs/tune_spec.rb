require 'spec_helper'

require 'puppet_x/puppetlabs/tune.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Tune do
  subject(:tune) { described_class.new(:unit_test => true) }

  before(:each) do
    suppress_standard_output
  end

  context 'with its supporting methods' do
    it 'can detect an unknown infrastructure' do
      tune.instance_variable_set(:@primary_masters,  [])
      expect(tune::unknown_pe_infrastructure?).to eq(true)
    end

    it 'can detect a monolithic infrastructure' do
      tune.instance_variable_set(:@console_hosts,  [])
      tune.instance_variable_set(:@puppetdb_hosts, [])
      tune.instance_variable_set(:@external_database_hosts, [])
      expect(tune::monolithic?).to eq(true)
      expect(tune::with_external_database?).to eq(false)
    end

    it 'can detect a split infrastructure' do
      tune.instance_variable_set(:@console_hosts,  ['console'])
      tune.instance_variable_set(:@puppetdb_hosts, ['puppetdb'])
      expect(tune::monolithic?).to eq(false)
    end

    it 'can detect a replica master' do
      tune.instance_variable_set(:@replica_masters, ['HA1'])
      expect(tune::with_ha?).to eq(true)
    end

    it 'can detect a compile master' do
      tune.instance_variable_set(:@compile_masters, ['compile'])
      expect(tune::with_compile_masters?).to eq(true)
    end

    it 'can detect an external database host' do
      tune.instance_variable_set(:@primary_masters,  ['master'])
      tune.instance_variable_set(:@console_hosts,    [])
      tune.instance_variable_set(:@puppetdb_hosts,   [])
      tune.instance_variable_set(:@external_database_hosts, ['postgresql'])
      expect(tune::with_external_database?).to eq(true)
    end

    it 'can detect the puppetdb service on a host' do
      tune.instance_variable_set(:@nodes_with_puppetdb, ['compile_master'])
      expect(tune::with_puppetdb?('compile_master')).to eq(true)
    end

    it 'can detect the database service on a host' do
      tune.instance_variable_set(:@nodes_with_database, ['master'])
      expect(tune::with_database?('master')).to eq(true)
    end

    # it 'can detect that JRuby9K is enabled for the puppetsever service' do
    # end

    it 'can extract common settings' do
      tune.instance_variable_set(:@tune_options, :common => true)
      tune.instance_variable_set(:@common_settings, {})
      collected_nodes = {
        'node_1' => { 'settings' => { 'a' => 1, 'b' => 'b' } },
        'node_2' => { 'settings' => { 'a' => 2, 'b' => 'b' } }
      }
      common_settings = { 'b' => 'b' }
      tune.instance_variable_set(:@collected_nodes, collected_nodes)
      expect(tune::extract_common_optimized_settings).to eq(common_settings)
    end

    it 'can enforce minimum system requirements' do
      tune.instance_variable_set(:@tune_options, :force => false)
      resources = { 'cpu' => 3, 'ram' => 8191 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(false)
      resources = { 'cpu' => 3, 'ram' => 8192 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(false)
      resources = { 'cpu' => 4, 'ram' => 8191 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(false)
      resources = { 'cpu' => 4, 'ram' => 8192 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(true)
    end

    it 'can disable minimum system requirements' do
      tune.instance_variable_set(:@tune_options, :force => true)
      resources = { 'cpu' => 3, 'ram' => 8191 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(true)
    end

    it 'can convert a string to bytes with a unit' do
      bytes_string = '16g'
      bytes = 17179869184
      expect(tune::string_to_bytes(bytes_string)).to eq(bytes)
    end

    it 'can convert a string to bytes without a unit' do
      bytes_string = '16'
      bytes = 17179869184
      expect(tune::string_to_bytes(bytes_string)).to eq(bytes)
    end

    it 'can read node resources from an inventory' do
      nodes = {
        'master' => { 'resources' => { 'cpu' => 8, 'ram' => '16g' } },
      }
      resources = { 'cpu' => 8, 'ram' => 16384 }
      tune.instance_variable_set(:@inventory, 'nodes' => nodes)
      expect(tune::get_resources_for_node('master')).to eq(resources)
    end

    it 'can convert inventory roles to profiles' do
      inventory = {
        'roles' => {
          'puppet_master_host' => 'master',
          'console_host'       => 'console',
          'puppetdb_host'      => 'puppetdb',
          'database_host'      => nil,
        },
        'components' => {
          'primary_master_replica' => [],
          'master'                 => [],
          'console'                => [],
          'puppetdb'               => [],
          'database'               => [],
          'amq::broker'            => [],
          'orchestrator'           => []
        }
      }
      result = {
        'roles' => {
          'puppet_master_host' => 'master',
          'console_host'       => 'console',
          'puppetdb_host'      => 'puppetdb',
          'database_host'      => nil,
        },
        'components' => {
          'primary_master_replica' => [],
          'master'                 => ['master'],
          'console'                => ['console'],
          'puppetdb'               => ['puppetdb'],
          'database'               => ['puppetdb'],
          'amq::broker'            => ['master'],
          'orchestrator'           => ['master']
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end
  end
end
