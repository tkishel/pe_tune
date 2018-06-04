require 'spec_helper'

require 'puppet_x/puppetlabs/tune'
require 'puppet_x/puppetlabs/tune/calculate.rb'

# TODO: Refactor these tests.

describe PuppetX::Puppetlabs::Tune::Calculate do
  # TODO: Replace/remove this unit_test workaround. my_hash = { key: 'value' }
  subject(:calculon) { described_class.new }

  context 'with a monolithic infrastructure, server size small' do
    Facter.add(:pe_server_version) { setcode { '2017.1.1' } }

    it 'can calculate master settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC'] = ''
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC']     = ''
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC']      = ''
      # settings['puppet_enterprise::profile::orchestrator::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 6451 },
        'MB_PER_JRUBY' => 512,
      }
      with_jruby_9k = false
      with_compile_masters = false
      with_external_postgresql = false
      expect(calculon::calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate master settings with compile masters' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC']       = ''
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC']     = ''
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC']      = ''
      # settings['puppet_enterprise::profile::orchestrator::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 5 },
        'RAM'          => { 'total' => 8192, 'used' => 6246 },
        'MB_PER_JRUBY' => 512,
      }
      with_jruby_9k = false
      with_compile_masters = true
      with_external_postgresql = false
      expect(calculon::calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate master host settings with external postgresql' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::master::jruby_max_active_instances'   => 2,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 512,
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC'] = ''
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC']     = ''
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC']      = ''
      # settings['puppet_enterprise::profile::orchestrator::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 4403 },
        'MB_PER_JRUBY' => 512,
      }
      with_jruby_9k = false
      with_compile_masters = false
      with_external_postgresql = true
      expect(calculon::calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size medium' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'    => '4096MB',
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::master::jruby_max_active_instances'   => 5,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '3840m', 'Xmx' => '3840m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 1024,
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC'] = ''
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC']     = ''
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC']      = ''
      # settings['puppet_enterprise::profile::orchestrator::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 8,     'used' => 7 },
        'RAM'          => { 'total' => 16384, 'used' => 12134 },
        'MB_PER_JRUBY' => 768,
      }
      with_jruby_9k = false
      with_compile_masters = false
      with_external_postgresql = false
      expect(calculon::calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size large' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'    => '8192MB',
        'puppet_enterprise::puppetdb::command_processing_threads' => 4,
        'puppet_enterprise::master::jruby_max_active_instances'   => 11,
        'puppet_enterprise::profile::master::java_args'           => { 'Xms' => '11264m', 'Xmx' => '11264m' },
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '3276m',  'Xmx' => '3276m' },
        'puppet_enterprise::profile::console::java_args'          => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::orchestrator::java_args'     => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'        => 2048,
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC']   = ''
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC'] = ''
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC']      = ''
      # settings['puppet_enterprise::profile::orchestrator::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 15 },
        'RAM'          => { 'total' => 32768, 'used' => 26828 },
        'MB_PER_JRUBY' => 1024,
      }
      with_jruby_9k = false
      with_compile_masters = false
      with_external_postgresql = false
      expect(calculon::calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with a split infrastructure, server size small' do
    it 'can calculate master or compile master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::master::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'         => { 'Xms' => '1536m', 'Xmx' => '1536m' },
      }
      # settings['puppet_enterprise::profile::master::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 1536 },
        'MB_PER_JRUBY' => 512,
      }
      with_jruby_9k = false
      with_activemq = false
      with_orchestrator = false
      expect(calculon::calculate_master_settings(resources, with_jruby_9k, with_activemq, with_orchestrator)).to eq([settings, totals])
    end

    it 'can calculate console host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::profile::console::java_args' => { 'Xms' => '4096m', 'Xmx' => '4096m' },
      }
      # settings['puppet_enterprise::profile::console::java_args']['XX:+UseG1GC'] = ''
      totals = { 'RAM' => { 'total' => 8192, 'used' => 4096 } }
      expect(calculon::calculate_console_settings(resources)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::database::shared_buffers'    => '2048MB',
      }
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU' => { 'total' => 4,    'used' => 3 },
        'RAM' => { 'total' => 8192, 'used' => 4096 },
      }
      with_external_postgresql = false
      expect(calculon::calculate_puppetdb_settings(resources, with_external_postgresql)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings with an external postgresql server' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '4096m', 'Xmx' => '4096m' },
      }
      # settings['puppet_enterprise::profile::puppetdb::java_args']['XX:+UseG1GC'] = ''
      totals = {
        'CPU' => { 'total' => 4, 'used' => 3 },
        'RAM' => { 'total' => 8192, 'used' => 4096 },
      }
      with_external_postgresql = true
      expect(calculon::calculate_puppetdb_settings(resources, with_external_postgresql)).to eq([settings, totals])
    end
  end

  context 'with any infrastructure' do
    it 'can calculate external postgresql host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers' => '2048MB',
      }
      totals = {
        'RAM' => { 'total' => 8192, 'used' => 2048 },
      }
      expect(calculon::calculate_external_postgresql_settings(resources)).to eq([settings, totals])
    end
  end

  context 'its private methods' do
    it 'can fit a setting based upon number of processors' do
      expect((calculon.send :fit_to_processors, 1,  'S', 'M', 'L')).to eq('S')
      expect((calculon.send :fit_to_processors, 4,  'S', 'M', 'L')).to eq('S')
      expect((calculon.send :fit_to_processors, 8,  'S', 'M', 'L')).to eq('M')
      expect((calculon.send :fit_to_processors, 16, 'S', 'M', 'L')).to eq('L')
      expect((calculon.send :fit_to_processors, 17, 'S', 'M', 'L')).to eq('L')
    end

    it 'can fit a setting based upon amount of memory' do
      expect((calculon.send :fit_to_memory, 4096,  'S', 'M', 'L')).to eq('S')
      expect((calculon.send :fit_to_memory, 8192,  'S', 'M', 'L')).to eq('S')
      expect((calculon.send :fit_to_memory, 16384, 'S', 'M', 'L')).to eq('M')
      expect((calculon.send :fit_to_memory, 32768, 'S', 'M', 'L')).to eq('L')
      expect((calculon.send :fit_to_memory, 32769, 'S', 'M', 'L')).to eq('L')
    end

    it 'can calculate the percentage of a resource limited to a minimum and maximum' do
      expect((calculon.send :clamp_percent_of_resource, 4096, 50, 1024, 3072)).to eq(2048)
      expect((calculon.send :clamp_percent_of_resource, 4096, 10, 1024, 3072)).to eq(1024)
      expect((calculon.send :clamp_percent_of_resource, 4096, 90, 1024, 3072)).to eq(3072)
    end
  end
end
