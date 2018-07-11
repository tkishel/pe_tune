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

  context 'its supporting methods' do
    it 'can detect an unknown infrastructure' do
      tune.instance_variable_set(:@primary_masters,  [])
      expect(tune::unknown_pe_infrastructure?).to eq(true)
    end

    it 'can detect a monolithic infrastructure' do
      tune.instance_variable_set(:@console_hosts,  [])
      tune.instance_variable_set(:@puppetdb_hosts, [])
      tune.instance_variable_set(:@external_database_hosts, [])
      expect(tune::monolithic?).to eq(true)
      expect(tune::with_external_postgresql?).to eq(false)
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

    it 'can detect an external postgresql server' do
      tune.instance_variable_set(:@primary_masters,  ['master'])
      tune.instance_variable_set(:@console_hosts,    [])
      tune.instance_variable_set(:@puppetdb_hosts,   [])
      tune.instance_variable_set(:@external_database_hosts, ['postgresql'])
      expect(tune::with_external_postgresql?).to eq(true)
    end

    # it 'can detect that JRuby9K is enabled for the puppetsever service' do
    # end

    it 'can extract common settings' do
      tune.instance_variable_set(:@option_common_settings, true)
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
      tune.instance_variable_set(:@option_no_minimum_system_requirements, true)
      resources = { 'cpu' => 3, 'ram' => 8191 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(true)
    end
  end
end
