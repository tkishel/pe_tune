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

  context 'helper methods' do
    it 'can detect a monolithic infrastructure' do
      tune.instance_variable_set(:@console_hosts,  [])
      tune.instance_variable_set(:@puppetdb_hosts, [])
      expect(tune::monolithic?).to eq(true)
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

    it 'can detect a monolithic infrastructure with an external postgresql server' do
      tune.instance_variable_set(:@primary_masters,  ['master'])
      tune.instance_variable_set(:@console_hosts,    [])
      tune.instance_variable_set(:@puppetdb_hosts,   [])
      tune.instance_variable_set(:@pe_database_host, 'postgresql')
      expect(tune::with_external_postgresql?).to eq(true)
    end

    it 'can detect a split infrastructure with an external postgresql server' do
      tune.instance_variable_set(:@primary_masters, ['master'])
      tune.instance_variable_set(:@console_hosts,   ['console'])
      tune.instance_variable_set(:@puppetdb_hosts,  ['puppetdb'])
      tune.instance_variable_set(:@pe_database_host, 'postgresql')
      expect(tune::with_external_postgresql?).to eq(true)
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

    it 'can not enforce minimum system requirements' do
      tune.instance_variable_set(:@option_no_minimum_system_requirements, true)
      resources = { 'cpu' => 3, 'ram' => 8191 }
      expect(tune::meets_minimum_system_requirements?(resources)).to eq(true)
    end

    # Refer to tune_calculate_spec.rb for testing of optimize_* methods.

    it 'can fit a setting based upon number of processors' do
      expect(tune::fit_to_processors(1,  'S', 'M', 'L')).to eq('S')
      expect(tune::fit_to_processors(4,  'S', 'M', 'L')).to eq('S')
      expect(tune::fit_to_processors(8,  'S', 'M', 'L')).to eq('M')
      expect(tune::fit_to_processors(16, 'S', 'M', 'L')).to eq('L')
      expect(tune::fit_to_processors(17, 'S', 'M', 'L')).to eq('L')
    end

    it 'can fit a setting based upon amount of memory' do
      expect(tune::fit_to_memory(4096,  'S', 'M', 'L')).to eq('S')
      expect(tune::fit_to_memory(8192,  'S', 'M', 'L')).to eq('S')
      expect(tune::fit_to_memory(16384, 'S', 'M', 'L')).to eq('M')
      expect(tune::fit_to_memory(32768, 'S', 'M', 'L')).to eq('L')
      expect(tune::fit_to_memory(32769, 'S', 'M', 'L')).to eq('L')
    end

    it 'can calculate the percentage of a resource limited to a minimum and maximum' do
      expect(tune::clamp_percent_of_resource(4096, 50, 1024, 3072)).to eq(2048)
      expect(tune::clamp_percent_of_resource(4096, 10, 1024, 3072)).to eq(1024)
      expect(tune::clamp_percent_of_resource(4096, 90, 1024, 3072)).to eq(3072)
    end

    it 'can detect the absense of JRuby 9K via PE Server Version' do
      Facter.clear
      Facter.add(:pe_server_version) { setcode { '2017.1.1' } }
      expect(tune::jruby_9k_enabled?).to eq(false)
    end

    it 'can detect JRuby 9K via PE Server Version' do
      Facter.clear
      Facter.add(:pe_server_version) { setcode { '2018.1.1' } }
      expect(tune::jruby_9k_enabled?).to eq(true)
    end
  end
end
