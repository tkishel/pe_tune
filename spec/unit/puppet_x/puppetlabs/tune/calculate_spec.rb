require 'spec_helper'

require 'puppet_x/puppetlabs/tune/calculate.rb'

describe PuppetX::Puppetlabs::Tune::Calculate do
  options = {}
  subject(:calculator) { described_class.new(options) }

  # Allows mergeups from PE 2018 LTS to STS. Revisit after PE 2018 is EOL.
  pe_2019_or_newer = Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')

  context 'with a monolithic infrastructure' do
    it 'can calculate master host settings, in vmpooler' do
      resources = {
        'cpu' => 2,
        'ram' => 6144,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 1,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '512m', 'Xmx' => '512m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '512m', 'Xmx' => '512m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m', 'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m', 'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 2,    'used' => 2 },
        'RAM'          => { 'total' => 6144, 'used' => 4608 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '512m'
        settings['totals']['RAM']['used'] += 512
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings, server size small' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 5120 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '512m'
        settings['totals']['RAM']['used'] += 512
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings, server size medium' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => '3840MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 5,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '3840m', 'Xmx' => '3840m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1152m', 'Xmx' => '1152m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '768m',  'Xmx' => '768m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 1024,
      }
      totals = {
        'CPU'          => { 'total' => 8,     'used' => 7 },
        'RAM'          => { 'total' => 16384, 'used' => 11392 },
        'MB_PER_JRUBY' => 768,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '640m'
        settings['totals']['RAM']['used'] += 640
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings, server size large' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => '7936MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 4,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 11,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '11264m', 'Xmx' => '11264m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '2380m',  'Xmx' => '2380m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '1024m',  'Xmx' => '1024m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 2048,
      }
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 15 },
        'RAM'          => { 'total' => 32768, 'used' => 25676 },
        'MB_PER_JRUBY' => 1024,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '1408m'
        settings['totals']['RAM']['used'] += 1408
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings with compile masters' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => true,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => '2048MB',
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 5632 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '512m'
        settings['totals']['RAM']['used'] += 512
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings with an external database' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => true,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => true,
        'console'      => true,
        'database'     => false,
        'orchestrator' => true,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1433m', 'Xmx' => '1433m' },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => 512,
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 4 },
        'RAM'          => { 'total' => 8192, 'used' => 3993 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = '512m'
        settings['totals']['RAM']['used'] += 512
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end
  end

  context 'with a split infrastructure' do
    it 'can calculate master host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => false,
        'with_extra_large'     => false
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => false,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => true,
        'puppetdb'     => false,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1536m', 'Xmx' => '1536m' },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => '512m',  'Xmx' => '512m' },
      }
      totals = {
        'CPU'          => { 'total' => 4,    'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 2048 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate console host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      node = { 'resources' => resources, 'infrastructure' => {}, 'type' => {}, 'classes' => {} }

      params = {
        'puppet_enterprise::profile::console::java_args' => { 'Xms' => '4096m', 'Xmx' => '4096m' },
      }
      totals = {
        'CPU' => { 'total' => 4,    'used' => 0 },
        'RAM' => { 'total' => 8192, 'used' => 4096 }
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_console_settings(node)).to eq(settings)
    end

    it 'can calculate puppetdb host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      classes = {
        'database' => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'      => 2,
        'puppet_enterprise::profile::puppetdb::java_args'              => { 'Xms' => '1280m', 'Xmx' => '1280m' },
        'puppet_enterprise::profile::database::shared_buffers'         => '2048MB',
        'puppet_enterprise::profile::database::autovacuum_max_workers' => 3,
        'puppet_enterprise::profile::database::autovacuum_work_mem'    => '341MB',
        'puppet_enterprise::profile::database::maintenance_work_mem'   => '1024MB',
        'puppet_enterprise::profile::database::max_connections'        => 1000,
        'puppet_enterprise::profile::database::work_mem'               => '8MB',
      }
      totals = {
        'CPU' => { 'total' => 4,    'used' => 2 },
        'RAM' => { 'total' => 8192, 'used' => 3328 },
      }
      settings = { 'params' => params, 'totals' => totals }
      expect(calculator::calculate_puppetdb_settings(node)).to eq(settings)
    end

    it 'can calculate puppetdb host settings with an external database' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      classes = {
        'database' => false,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => '3584m', 'Xmx' => '3584m' },
      }
      totals = {
        'CPU' => { 'total' => 4, 'used' => 2 },
        'RAM' => { 'total' => 8192, 'used' => 3584 },
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_puppetdb_settings(node)).to eq(settings)
    end
  end

  context 'with a monolithic or split infrastructure' do
    it 'can calculate compile master host settings' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => true,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => true,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => false,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 7,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '5376m', 'Xmx' => '5376m' },
      }
      totals = {
        'CPU'          => { 'total' => 8,    'used' => 7 },
        'RAM'          => { 'total' => 16384, 'used' => 5376 },
        'MB_PER_JRUBY' => 768,
      }
      settings = { 'params' => params, 'totals' => totals }
      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate compile master host settings with puppetdb' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => false,
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => true,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 4,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '3174m', 'Xmx' => '3174m' },
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 11,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '11264m', 'Xmx' => '11264m' },
      }
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 15 },
        'RAM'          => { 'total' => 32768, 'used' => 14438 },
        'MB_PER_JRUBY' => 1024,
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate database host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => false,
        'with_extra_large'     => false,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => {} }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'         => '2048MB',
        'puppet_enterprise::profile::database::autovacuum_max_workers' => 3,
        'puppet_enterprise::profile::database::autovacuum_work_mem'    => '341MB',
        'puppet_enterprise::profile::database::maintenance_work_mem'   => '1024MB',
        'puppet_enterprise::profile::database::max_connections'        => 1000,
        'puppet_enterprise::profile::database::work_mem'               => '8MB',
      }
      totals = {
        'CPU' => { 'total' => 4,    'used' => 0 },
        'RAM' => { 'total' => 8192, 'used' => 2048 },
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_database_settings(node)).to eq(settings)
    end
  end

  context 'with a monolithic infrastructure with an extra large reference architecture' do
    it 'can calculate compile master host settings with puppetdb, server size small' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => true,
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => true,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 2,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 4,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '716m', 'Xmx' => '716m' },
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '1024m', 'Xmx' => '1024m' },
      }
      totals = {
        'CPU'          => { 'total' => 4,     'used' => 3 },
        'RAM'          => { 'total' => 8192, 'used' => 1740 },
        'MB_PER_JRUBY' => 512,
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate compile master host settings with puppetdb, server size medium' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => true,
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => true,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 4,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 8,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '1536m', 'Xmx' => '1536m' },
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 5,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '3840m', 'Xmx' => '3840m' },
      }
      totals = {
        'CPU'          => { 'total' => 8,     'used' => 7 },
        'RAM'          => { 'total' => 16384, 'used' => 5376 },
        'MB_PER_JRUBY' => 768,
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate compile master host settings with puppetdb, server size large' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
        'with_extra_large'     => true,
      }
      type = {
        'is_monolithic_master' => false,
        'is_replica_master'    => false,
        'is_compile_master'    => true,
        'with_jruby9k_enabled' => false,
      }
      classes = {
        'amq::broker'  => false,
        'console'      => false,
        'database'     => false,
        'orchestrator' => false,
        'puppetdb'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => type, 'classes' => classes }

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 3,
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 6,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 12,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => '3174m', 'Xmx' => '3174m' },
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 11,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => '11264m', 'Xmx' => '11264m' },
      }
      totals = {
        'CPU'          => { 'total' => 16,    'used' => 14 },
        'RAM'          => { 'total' => 32768, 'used' => 14438 },
        'MB_PER_JRUBY' => 1024,
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate database host settings' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => false,
        'with_compile_masters' => false,
        'with_extra_large'     => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => {} }

      params = {
        'puppet_enterprise::profile::database::shared_buffers'         => '2048MB',
        'puppet_enterprise::profile::database::autovacuum_max_workers' => 3,
        'puppet_enterprise::profile::database::autovacuum_work_mem'    => '341MB',
        'puppet_enterprise::profile::database::maintenance_work_mem'   => '1024MB',
        'puppet_enterprise::profile::database::max_connections'        => 1000,
        'puppet_enterprise::profile::database::work_mem'               => '8MB',
      }
      totals = {
        'CPU' => { 'total' => 4,    'used' => 0 },
        'RAM' => { 'total' => 8192, 'used' => 2048 },
      }
      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_database_settings(node)).to eq(settings)
    end
  end

  context 'with its supporting methods' do
    it 'can calculate a reasonable sample of agent runs based upon node count and run interval' do
      expect((calculator.send :calculate_run_sample, 1,    30)).to eq(2880)
      expect((calculator.send :calculate_run_sample, 5000,  0)).to eq(5000)
      expect((calculator.send :calculate_run_sample, 5000, 30)).to eq(10000)
    end

    it 'can calculate the theoretical maximum number of nodes that can managed by an infrastructure' do
      expect((calculator.send :calculate_maximum_nodes, 20, 1, 30)).to eq(1)
    end

    it 'can calculate the theoretical minimum number of jrubies required for an infrastructure' do
      expect((calculator.send :calculate_minimum_jrubies, 100, 20, 30)).to eq(134)
    end

    it 'can calculate the default memory reserved for the operating system' do
      expect((calculator.send :memory_reserved_for_os)).to eq(1024)
    end

    it 'can calculate the optional memory reserved for the operating system' do
      calculator.instance_variable_set(:@options, :memory_reserved_for_os => 2048)
      expect((calculator.send :memory_reserved_for_os)).to eq(2048)
    end

    it 'can calculate processor based values' do
      expect((calculator.send :calculate_cpu, 8, 0,  25, 1, 7)).to eq(2)
      expect((calculator.send :calculate_cpu, 8, 0,  50, 1, 7)).to eq(4)
      expect((calculator.send :calculate_cpu, 8, 0, 100, 1, 7)).to eq(7)

      expect((calculator.send :calculate_cpu, 8, 8, 100, 1, 7)).to eq(nil)
    end

    it 'can calculate memory (total minus memory reserved for the operating system) based values' do
      expect((calculator.send :calculate_ram, 16384, 0,  25, 1024,  8192)).to eq(3840)
      expect((calculator.send :calculate_ram, 16384, 0,  50, 1024,  8192)).to eq(7680)
      expect((calculator.send :calculate_ram, 16384, 0, 100, 1024, 16384)).to eq(15360)

      expect((calculator.send :calculate_ram, 16384, 16384, 100, 1024, 16384)).to eq(nil)
    end

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
      expect((calculator.send :percent_value_within_min_max, 4, 25, 2, 1)).to eq(2)
      expect((calculator.send :percent_value_within_min_max, 4, 25, 2, 2)).to eq(2)
      expect((calculator.send :percent_value_within_min_max, 4096, 50, 1024, 3072)).to eq(2048)
      expect((calculator.send :percent_value_within_min_max, 4096, 10, 1024, 3072)).to eq(1024)
      expect((calculator.send :percent_value_within_min_max, 4096, 90, 1024, 3072)).to eq(3072)
    end

    it 'can test if a number is within a percentage of another number' do
      expect((calculator.send :within_percent?, 80,  100, 5)).to eq(false)
      expect((calculator.send :within_percent?, 95,  100, 5)).to eq(true)
      expect((calculator.send :within_percent?, 100, 100, 5)).to eq(false)
    end

    it 'can calculate the nearest power of two' do
      expect((calculator.send :nearest_power_of_two,  511)).to eq(512)
      expect((calculator.send :nearest_power_of_two,  512)).to eq(512)
      expect((calculator.send :nearest_power_of_two,  513)).to eq(512)
      expect((calculator.send :nearest_power_of_two,  767)).to eq(512)
      expect((calculator.send :nearest_power_of_two,  768)).to eq(1024)
      expect((calculator.send :nearest_power_of_two, 1023)).to eq(1024)
      expect((calculator.send :nearest_power_of_two, 1024)).to eq(1024)
      expect((calculator.send :nearest_power_of_two, 1025)).to eq(1024)
    end
  end
end
