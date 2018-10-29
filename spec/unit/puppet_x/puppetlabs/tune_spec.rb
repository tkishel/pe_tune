require 'spec_helper'

require 'puppet_x/puppetlabs/tune.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Tune do
  # Disable the initialize method to test just the supporting methods.
  subject(:tune) { described_class.new(:unit_test => true) }

  before(:each) do
    suppress_standard_output
  end

  context 'with its supporting methods' do
    it 'can detect an unknown infrastructure' do
      nodes = { 'primary_masters' => [] }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::unknown_infrastructure?).to eq(true)
    end

    it 'can detect a monolithic infrastructure' do
      nodes = {
        'console_hosts'  => [],
        'puppetdb_hosts' => [],
      }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::monolithic?).to eq(true)
    end

    it 'can detect a split infrastructure' do
      nodes = {
        'console_hosts'  => ['console'],
        'puppetdb_hosts' => ['puppetdb'],
      }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::monolithic?).to eq(false)
    end

    it 'can detect a replica master' do
      nodes = { 'replica_masters' => ['replica'] }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::with_ha?).to eq(true)
    end

    it 'can detect compile masters' do
      nodes = { 'compile_masters' => ['compile'] }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::with_compile_masters?).to eq(true)
    end

    it 'can detect an external database host' do
      nodes = {
        'primary_masters' => ['master'],
        'database_hosts'  => ['postgresql'],
      }
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::with_external_database?).to eq(true)
    end

    it 'can detect local and external databases' do
      nodes_with_class = {
        'database' => ['master', 'postgresql']
      }
      nodes = {
        'primary_masters' => ['master'],
        'replica_masters' => [],
        'database_hosts'  => ['master', 'postgresql'],
      }
      tune.instance_variable_set(:@nodes_with_class, nodes_with_class)
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::with_local_and_external_databases?).to eq(true)
    end

    it 'can detect puppetdb on all masters' do
      nodes_with_class = {
        'puppetdb' => ['master', 'replica', 'compile']
      }
      nodes = {
        'primary_masters' => ['master'],
        'replica_masters' => ['replica'],
        'compile_masters' => ['compile'],
      }
      tune.instance_variable_set(:@nodes_with_class, nodes_with_class)
      tune.instance_variable_set(:@nodes_with_role, nodes)

      expect(tune::with_puppetdb_on_all_masters?).to eq(true)
    end

    it 'can detect a class on a host' do
      nodes_with_class = { 'console' => ['console'] }
      tune.instance_variable_set(:@nodes_with_class, nodes_with_class)

      expect(tune::node_with_class?('console', 'console')).to eq(true)
    end

    # it 'can detect that JRuby9K is enabled for the puppetsever service' do
    # end

    it 'can extract common settings' do
      tune.instance_variable_set(:@options, :common => true)
      tune.instance_variable_set(:@collected_settings_common, {})
      collected_nodes = {
        'node_1' => {
          'settings' => {
            'params' => {
              'a' => 1,
              'b' => 'b'
            }
          }
        },
        'node_2' => {
          'settings' => {
            'params' => {
              'a' => 2,
              'b' => 'b'
            }
          }
        }
      }
      collected_nodes_without_common_settings = {
        'node_1' => { 'settings' => { 'params' => { 'a' => 1 } } },
        'node_2' => { 'settings' => { 'params' => { 'a' => 2 } } }
      }
      collected_settings_common = { 'b' => 'b' }

      tune.instance_variable_set(:@collected_nodes, collected_nodes)
      tune::collect_optimized_settings_common_to_all_nodes

      expect(tune.instance_variable_get(:@collected_settings_common)).to eq(collected_settings_common)
      expect(tune.instance_variable_get(:@collected_nodes)).to eq(collected_nodes_without_common_settings)
    end

    it 'can enforce minimum system requirements' do
      tune.instance_variable_set(:@options, :force => false)

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
      tune.instance_variable_set(:@options, :force => true)
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

    it 'can convert a string to megabytes with a unit' do
      bytes_string = '1g'
      bytes = 1024
      expect(tune::string_to_megabytes(bytes_string)).to eq(bytes)
    end

    it 'can convert a string to megabytes without a unit' do
      bytes_string = '1024'
      bytes = 1024
      expect(tune::string_to_megabytes(bytes_string)).to eq(bytes)
    end
  end
end
