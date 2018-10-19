require 'spec_helper'

require 'puppet_x/puppetlabs/tune/inventory.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Tune::Inventory do
  subject(:inventory) { described_class.new }

  context 'with its supporting methods' do
    let(:empty_roles) do
      {
        'puppet_master_host'     => nil,
        'console_host'           => nil,
        'puppetdb_host'          => [],
        'database_host'          => nil,
        'primary_master_replica' => nil,
        'compile_master'         => [],
        'compile_masters_xl'     => [],
        'database_hosts_xl'      => []
      }
    end

    let(:empty_classes) do
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

    it 'can use the local system as inventory' do
      allow(Puppet::Util::Execution).to receive(:execute).with('hostname -f').and_return('master.example.com')
      allow(Puppet::Util::Execution).to receive(:execute).with('nproc --all').and_return('4')
      allow(Puppet::Util::Execution).to receive(:execute).with('free -b | grep Mem').and_return('Mem: 8589934592')
      output = {
        'nodes' => {
          'master.example.com' => {
            'resources' => {
              'cpu' => '4',
              'ram' => '8589934592b',
            }
          }
        },
        'roles' => {
          'puppet_master_host'     => 'master.example.com',
          'console_host'           => nil,
          'puppetdb_host'          => [],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => [],
          'compile_masters_xl'     => [],
          'database_hosts_xl'      => []
        },
        'classes' => {
          'master'                 => ['master.example.com'].to_set,
          'console'                => ['master.example.com'].to_set,
          'puppetdb'               => ['master.example.com'].to_set,
          'database'               => ['master.example.com'].to_set,
          'amq::broker'            => ['master.example.com'].to_set,
          'orchestrator'           => ['master.example.com'].to_set,
          'primary_master'         => ['master.example.com'].to_set,
          'primary_master_replica' => [].to_set,
          'compile_master'         => [].to_set
        }
      }

      inventory::read_inventory_from_local_system

      expect(inventory.instance_variable_get(:@nodes)).to   eq(output['nodes'])
      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert mono inventory roles to classes' do
      inputs = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert mono inventory roles to classes with a compile master' do
      inputs = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => ['compile']
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => nil,
          'puppetdb_host'          => nil,
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => ['compile']
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert split inventory roles to classes' do
      inputs = {
        'nodes' => {},
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert split inventory roles to classes with a database host' do
      inputs = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert split inventory roles to classes with an array of puppetdb hosts' do
      inputs = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => nil,
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end

    it 'can convert split inventory roles to classes with a database host and an array of puppetdb hosts' do
      inputs = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => empty_classes
      }
      output = {
        'roles' => {
          'puppet_master_host'     => 'master',
          'console_host'           => 'console',
          'puppetdb_host'          => ['puppetdb1', 'puppetdb2'],
          'database_host'          => 'database',
          'primary_master_replica' => nil,
          'compile_master'         => nil
        },
        'classes' => {
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

      expect(inventory.instance_variable_set(:@roles,   inputs['roles']))
      expect(inventory.instance_variable_set(:@classes, inputs['classes']))

      inventory::convert_inventory_roles_to_classes

      expect(inventory.instance_variable_get(:@roles)).to   eq(output['roles'])
      expect(inventory.instance_variable_get(:@classes)).to eq(output['classes'])
    end
  end
end
