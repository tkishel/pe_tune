require 'spec_helper'

require 'puppet_x/puppetlabs/tune/calculate.rb'

describe PuppetX::Puppetlabs::Tune::Calculate do
  subject(:calculator) { described_class.new }

  context 'with a monolithic infrastructure, server size small' do
    Facter.add(:pe_server_version) { setcode { '2017.1.1' } }

    it 'can calculate master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => true,
        'with_compile_masters' => false,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'                => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 6451 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size medium' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      configuration = {
        'is_monolithic_master' => true,
        'with_compile_masters' => false,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'                => '4096MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 5,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '3840m', 'Xmx' => '3840m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 1024,
      }
      totals = {
        'CPU'          => { 'total' => 8,     'used' => 7 },
        'RAM'          => { 'total' => 16384, 'used' => 12134 },
        'MB_PER_JRUBY' => 768,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure, server size large' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      configuration = {
        'is_monolithic_master' => true,
        'with_compile_masters' => false,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'                => '8192MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 4,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 11,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '11264m', 'Xmx' => '11264m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '3276m',  'Xmx' => '3276m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 2048,
      }
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 15 },
        'RAM'          => { 'total' => 32768, 'used' => 26828 },
        'MB_PER_JRUBY' => 1024,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end
  end

  context 'with a monolithic infrastructure' do
    Facter.add(:pe_server_version) { setcode { '2017.1.1' } }

    it 'can calculate master host settings with compile masters' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => true,
        'with_compile_masters' => true,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::profile::database::shared_buffers'                => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 3,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1638m', 'Xmx' => '1638m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 5 },
        'RAM'          => { 'total' => 8192, 'used' => 6246 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end

    it 'can calculate master host settings with an external database' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => true,
        'with_compile_masters' => false,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => true,
        'console'      => true,
        'database'     => false,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '2048m', 'Xmx' => '2048m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '819m',  'Xmx' => '819m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 4403 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end
  end

  context 'with a split infrastructure' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => false,
        'with_compile_masters' => false,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => true,
        'puppetdb'     => false,
      }
      settings = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1536m', 'Xmx' => '1536m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 2048 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end

    it 'can calculate console host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      settings = {
        'puppet_enterprise::profile::console::java_args' => { 'Xms' => '4096m', 'Xmx' => '4096m' },
      }
      totals = { 'RAM' => { 'total' => 8192, 'used' => 4096 } }
      expect(calculator::calculate_console_settings(resources)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      components = {
        'database' => true,
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
      expect(calculator::calculate_puppetdb_settings(resources, components)).to eq([settings, totals])
    end

    it 'can calculate puppetdb host settings with an external database' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      components = {
        'database' => false,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 3,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '4096m', 'Xmx' => '4096m' },
      }
      totals = {
        'CPU' => { 'total' => 4, 'used' => 3 },
        'RAM' => { 'total' => 8192, 'used' => 4096 },
      }
      expect(calculator::calculate_puppetdb_settings(resources, components)).to eq([settings, totals])
    end
  end

  context 'with any infrastructure' do
    it 'can calculate compile master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => false,
        'with_compile_masters' => true,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => false,
      }
      settings = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1536m', 'Xmx' => '1536m' },
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 1536 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end

    it 'can calculate compile master host settings with puppetdb' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      configuration = {
        'is_monolithic_master' => false,
        'with_compile_masters' => true,
        'with_jruby9k_enabled' => false,
      }
      components = {
        'activemq'     => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => true,
      }
      settings = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '819m', 'Xmx' => '819m' },
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 1843 },
        'MB_PER_JRUBY' => 512,
      }
      expect(calculator::calculate_master_settings(resources, configuration, components)).to eq([settings, totals])
    end

    it 'can calculate database host settings' do
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
      expect(calculator::calculate_database_settings(resources)).to eq([settings, totals])
    end
  end

  context 'its supporting methods' do
    it 'can calculate a setting based upon number of processors' do
      expect((calculator.send :fit_to_processors, 1,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_processors, 4,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_processors, 8,  'S', 'M', 'L')).to eq('M')
      expect((calculator.send :fit_to_processors, 16, 'S', 'M', 'L')).to eq('L')
      expect((calculator.send :fit_to_processors, 17, 'S', 'M', 'L')).to eq('L')
    end

    it 'can calculate a setting based upon amount of memory' do
      expect((calculator.send :fit_to_memory, 4096,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_memory, 8192,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_memory, 16384, 'S', 'M', 'L')).to eq('M')
      expect((calculator.send :fit_to_memory, 32768, 'S', 'M', 'L')).to eq('L')
      expect((calculator.send :fit_to_memory, 32769, 'S', 'M', 'L')).to eq('L')
    end

    it 'can calculate the percentage of a resource limited to a minimum and maximum' do
      expect((calculator.send :clamp_percent_of_resource, 4096, 50, 1024, 3072)).to eq(2048)
      expect((calculator.send :clamp_percent_of_resource, 4096, 10, 1024, 3072)).to eq(1024)
      expect((calculator.send :clamp_percent_of_resource, 4096, 90, 1024, 3072)).to eq(3072)
    end
  end
end
