require 'spec_helper'

require 'puppet_x/puppetlabs/tune.rb'

# TODO: Refactor these tests.

describe PuppetX::Puppetlabs::Tune do
  # TODO: Replace/remove this unit_test workaround.
  subject(:tune) { described_class.new(:unit_test => true) }

  context 'with a monolithic infrastructure, server size small' do
    Facter.add(:pe_server_version) { setcode { '2017.1.1' } }

    it 'can calculate master settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB'
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 6451 },
        'MB_PER_JRUBY' => 512
      }
      with_compile_masters = false
      with_external_postgresql = false
      expect(tune::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate master settings with compile masters' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB'
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 6246 },
        'MB_PER_JRUBY' => 512
      }
      with_compile_masters = true
      with_external_postgresql = false
      expect(tune::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate master host settings with external postgresql' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' }
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 4403 },
        'MB_PER_JRUBY' => 512
      }
      with_compile_masters = false
      with_external_postgresql = true
      expect(tune::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size medium' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 8,
        'ram' => 16384
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances'   => 6,
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '4608m', 'Xmx' => '4608m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 1024,
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '4096MB'
      }
      totals = {
        'CPU'          => { 'total' => 8,     'used' => 8 },
        'RAM'          => { 'total' => 16384, 'used' => 12902 },
        'MB_PER_JRUBY' => 768
      }
      with_compile_masters = false
      with_external_postgresql = false
      expect(tune::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size large' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 16,
        'ram' => 32768
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances'   => 10,
        'puppet_enterprise::puppetdb::command_processing_threads' => 4,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '10240m', 'Xmx' => '10240m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '3276m',  'Xmx' => '3276m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 2048,
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '8192MB'
      }
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 14 },
        'RAM'          => { 'total' => 32768, 'used' => 25804 },
        'MB_PER_JRUBY' => 1024
      }
      with_compile_masters = false
      with_external_postgresql = false
      expect(tune::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a split infrastructure, server size small' do
    it 'can calculate master or compile master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'         => { 'Xms' => '1536m', 'Xmx' => '1536m' }
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 1536 },
        'MB_PER_JRUBY' => 512
      }
      with_activemq = false
      with_orchestrator = false
      expect(tune::calculate_master_settings(resources, with_activemq, with_orchestrator)).to eq([settings, totals])
    end

    it 'can calculate console host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::profile::console::java_args' => { 'Xms' => '4096m', 'Xmx' => '4096m' }
      }
      totals = { 'RAM' => { 'total' => 8192, 'used' => 4096 } }
      expect(tune::calculate_console_settings(resources)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '2048m',  'Xmx' => '2048m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB'
      }
      totals = {
        'CPU' => { 'total' => 4,    'used' => 3 },
        'RAM' => { 'total' => 8192, 'used' => 4096 }
      }
      with_external_postgresql = false
      expect(tune::calculate_puppetdb_settings(resources, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings with an external postgresql server' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '4096m',  'Xmx' => '4096m' }
      }
      totals = {
        'CPU' => { 'total' => 4, 'used' => 3 },
        'RAM' => { 'total' => 8192, 'used' => 4096 }
      }
      with_external_postgresql = true
      expect(tune::calculate_puppetdb_settings(resources, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with any infrastructure' do
    it 'can calculate external postgresql host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers' => '2048MB'
      }
      totals = {
        'RAM' => { 'total' => 8192, 'used' => 2048 }
      }
      expect(tune::calculate_external_postgresql_settings(resources)).to eq([settings, totals])
    end
  end
end
