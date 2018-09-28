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
    let(:empty_components) do
      {
        'master'                 => [].to_set,
        'console'                => [].to_set,
        'puppetdb'               => [].to_set,
        'database'               => [].to_set,
        'amq::broker'            => [].to_set,
        'orchestrator'           => [].to_set,
        'primary_master'         => [].to_set,
        'primary_master_replica' => [].to_set,
        'compile_master'         => [].to_set
      }
    end

    it 'can detect an unknown infrastructure' do
      nodes = { 'primary_masters' => [] }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::unknown_pe_infrastructure?).to eq(true)
    end

    it 'can detect a monolithic infrastructure' do
      nodes = {
        'console_hosts'  => [],
        'puppetdb_hosts' => [],
      }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::monolithic?).to eq(true)
    end

    it 'can detect a split infrastructure' do
      nodes = {
        'console_hosts'  => ['console'],
        'puppetdb_hosts' => ['puppetdb'],
      }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::monolithic?).to eq(false)
    end

    it 'can detect a replica master' do
      nodes = { 'replica_masters' => ['replica'] }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::with_ha?).to eq(true)
    end

    it 'can detect compile masters' do
      nodes = { 'compile_masters' => ['compile'] }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::with_compile_masters?).to eq(true)
    end

    it 'can detect an external database host' do
      nodes = {
        'primary_masters' => ['master'],
        'console_hosts'  => [],
        'puppetdb_hosts' => [],
        'database_hosts' => ['postgresql'],
      }
      tune.instance_variable_set(:@nodes, nodes)
      expect(tune::with_external_database?).to eq(true)
    end

    it 'can detect the console service on a host' do
      nodes_with = { 'console' => ['console'] }
      tune.instance_variable_set(:@nodes_with, nodes_with)
      expect(tune::with_console?('console')).to eq(true)
    end

    it 'can detect the database service on a host' do
      nodes = { 'compile_masters' => ['compile'] }
      tune.instance_variable_set(:@nodes, nodes)
      nodes_with = { 'database' => ['database'] }
      tune.instance_variable_set(:@nodes_with, nodes_with)
      expect(tune::with_database?('database')).to eq(true)
    end

    it 'can detect the orchestrator service on a host' do
      nodes = { 'compile_masters' => ['compile'] }
      tune.instance_variable_set(:@nodes, nodes)
      nodes_with = { 'orchestrator' => ['orchestrator'] }
      tune.instance_variable_set(:@nodes_with, nodes_with)
      expect(tune::with_orchestrator?('orchestrator')).to eq(true)
    end

    it 'can detect the puppetdb service on a host' do
      nodes_with = { 'puppetdb' => ['puppetdb'] }
      tune.instance_variable_set(:@nodes_with, nodes_with)
      expect(tune::with_puppetdb?('puppetdb')).to eq(true)
    end

    # it 'can detect that JRuby9K is enabled for the puppetsever service' do
    # end

    it 'can extract common settings' do
      tune.instance_variable_set(:@tune_options, :common => true)
      tune.instance_variable_set(:@collected_common_settings, {})
      collected_nodes = {
        'node_1' => { 'settings' => { 'a' => 1, 'b' => 'b' } },
        'node_2' => { 'settings' => { 'a' => 2, 'b' => 'b' } }
      }
      common_settings = { 'b' => 'b' }
      tune.instance_variable_set(:@collected_nodes, collected_nodes)
      expect(tune::collect_common_optimized_settings).to eq(common_settings)
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

    it 'can read node resources from an inventory' do
      nodes = {
        'master' => { 'resources' => { 'cpu' => 8, 'ram' => '16g' } },
      }
      resources = { 'cpu' => 8, 'ram' => 16384 }
      tune.instance_variable_set(:@inventory, 'nodes' => nodes)
      expect(tune::get_resources_for_node('master')).to eq(resources)
    end

    it 'can use the local system as inventory' do
      allow(Puppet::Util::Execution).to receive(:execute).with('hostname -f').and_return('master.example.com')
      allow(Puppet::Util::Execution).to receive(:execute).with('nproc --all').and_return('4')
      allow(Puppet::Util::Execution).to receive(:execute).with('free -b | grep Mem').and_return('Mem: 8589934592')
      inventory = {
        'nodes' => {
          'master.example.com' => {
            'resources' => {
              'cpu' => '4',
              'ram' => '8589934592b',
            }
          }
        },
        'roles' => {
          'puppet_master_host' => 'master.example.com',
        },
        'components' => empty_components
      }
      expect(tune::use_local_system_as_inventory).to eq(inventory)
    end

    it 'can convert mono inventory roles to profiles' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => {
          'master'                 => ['master'].to_set,
          'console'                => ['master'].to_set,
          'puppetdb'               => ['master'].to_set,
          'database'               => ['master'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end

    it 'can convert mono inventory roles to profiles with a compile master' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => ['compile']
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => ['compile']
        },
        'components' => {
          'master'                 => ['master', 'compile'].to_set,
          'console'                => ['master'].to_set,
          'puppetdb'               => ['master'].to_set,
          'database'               => ['master'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => ['compile'].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end

    it 'can convert split inventory roles to profiles' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => {
          'master'                 => ['master'].to_set,
          'console'                => ['console'].to_set,
          'puppetdb'               => ['puppetdb'].to_set,
          'database'               => ['puppetdb'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end

    it 'can convert split inventory roles to profiles with a database host' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => {
          'master'                 => ['master'].to_set,
          'console'                => ['console'].to_set,
          'puppetdb'               => ['puppetdb'].to_set,
          'database'               => ['database'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end

    it 'can convert split inventory roles to profiles with an array of puppetdb hosts' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => {
          'master'                 => ['master'].to_set,
          'console'                => ['console'].to_set,
          'puppetdb'               => ['puppetdb1', 'puppetdb2'].to_set,
          'database'               => ['puppetdb1'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end

    it 'can convert split inventory roles to profiles with a database host and an array of puppetdb hosts' do
      inventory = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => empty_components
      }
      result = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'components' => {
          'master'                 => ['master'].to_set,
          'console'                => ['console'].to_set,
          'puppetdb'               => ['puppetdb1', 'puppetdb2'].to_set,
          'database'               => ['database'].to_set,
          'amq::broker'            => ['master'].to_set,
          'orchestrator'           => ['master'].to_set,
          'primary_master'         => ['master'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }
      expect(tune::convert_inventory_roles_to_components(inventory)).to eq(result)
    end
  end
end
