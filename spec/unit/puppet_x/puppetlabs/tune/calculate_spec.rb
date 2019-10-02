require 'spec_helper'

require 'puppet_x/puppetlabs/tune/calculate.rb'

describe PuppetX::Puppetlabs::Tune::Calculate do
  options = {}
  subject(:calculator) { described_class.new(options) }

  # Allows mergeups in the PE implementation of this class.
  pe_2019_or_newer = Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')

  pe_2019_2_or_newer = Gem::Version.new(Puppet.version) >= Gem::Version.new('6.9.0')

  ram_per_jruby_code_cache = 128

  percent_ram_database     = 0.25
  percent_ram_puppetdb     = 0.10
  percent_ram_console      = 0.08
  percent_ram_orchestrator = 0.08
  percent_ram_activemq     = 0.08

  percent_ram_puppetdb_with_compilers = 0.20
  percent_ram_puppetdb_split          = 0.25
  percent_ram_puppetdb_split_external = 0.50

  minimum_ram_database     = 2048
  # maximum_ram_database   = 16384

  # minimum_ram_puppetdb   = 512
  # maximum_ram_puppetdb   = 8192

  minimum_ram_puppetserver = 512

  minimum_ram_orchestrator = 512
  maximum_ram_orchestrator = 1024

  minimum_ram_console      = 512
  maximum_ram_console      = 1024

  minimum_ram_activemq     = 512
  maximum_ram_activemq     = 1024

  context 'with a monolithic infrastructure' do
    it 'can calculate master host settings, in vmpooler' do
      resources = {
        'cpu' => 2,
        'ram' => 6144,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
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

      ram_database     = minimum_ram_database
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = minimum_ram_puppetserver
      ram_orchestrator = minimum_ram_orchestrator
      ram_console      = minimum_ram_console
      ram_activemq     = minimum_ram_activemq
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 1,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        settings['totals']['RAM']['used'] += reserved_code_cache
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

      ram_database     = minimum_ram_database
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 1024
      ram_orchestrator = (resources['ram'] * percent_ram_orchestrator).to_i
      ram_console      = (resources['ram'] * percent_ram_console).to_i
      ram_activemq     = (resources['ram'] * percent_ram_activemq).to_i
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        settings['totals']['RAM']['used'] += reserved_code_cache
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

      ram_database     = (resources['ram'] * percent_ram_database).to_i
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 3840
      ram_orchestrator = maximum_ram_orchestrator
      ram_console      = maximum_ram_console
      ram_activemq     = maximum_ram_activemq
      mb_per_jruby     = 768

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 5,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        settings['totals']['RAM']['used'] += reserved_code_cache
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings, server size large, with and without orchestrator jruby' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => false,
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

      ram_database     = (resources['ram'] * percent_ram_database).to_i
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 11264
      ram_orchestrator = maximum_ram_orchestrator
      ram_console      = maximum_ram_console
      ram_activemq     = maximum_ram_activemq
      mb_per_jruby     = 1024

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'             => 4,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 11,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        if pe_2019_2_or_newer
          node['type']['with_orchestrator_jruby'] = true
          settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] -= 1
          settings['totals']['CPU']['used'] -= 1
          reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
          settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
          settings['params']['puppet_enterprise::profile::master::java_args']       = { 'Xms' => '10240m', 'Xmx' => '10240m' }
          settings['params']['puppet_enterprise::profile::orchestrator::java_args'] = { 'Xms' => '2048m',  'Xmx' => '2048m' }
        else
          reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
          settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        end
        settings['totals']['RAM']['used'] += reserved_code_cache
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings with compilers' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
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

      ram_database     = minimum_ram_database
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb_with_compilers).to_i
      ram_puppetserver = 1024
      ram_orchestrator = (resources['ram'] * percent_ram_orchestrator).to_i
      ram_console      = (resources['ram'] * percent_ram_console).to_i
      ram_activemq     = (resources['ram'] * percent_ram_activemq).to_i
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::profile::database::shared_buffers'                => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        settings['totals']['RAM']['used'] += reserved_code_cache
        settings['totals']['RAM']['used'] -= settings['params']['puppet_enterprise::profile::amq::broker::heap_mb']
        settings['params'].delete('puppet_enterprise::profile::amq::broker::heap_mb')
      end

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate master host settings with compilers with an external database' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
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

      ram_database     = 0
      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb_with_compilers).to_i
      ram_puppetserver = 1024
      ram_orchestrator = (resources['ram'] * percent_ram_orchestrator).to_i
      ram_console      = (resources['ram'] * percent_ram_console).to_i
      ram_activemq     = (resources['ram'] * percent_ram_activemq).to_i
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
        'puppet_enterprise::profile::console::java_args'                      => { 'Xms' => "#{ram_console}m",      'Xmx' => "#{ram_console}m" },
        'puppet_enterprise::profile::amq::broker::heap_mb'                    => ram_activemq,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_database + ram_puppetdb + ram_puppetserver + ram_orchestrator + ram_console + ram_activemq
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      if pe_2019_or_newer
        node['type']['with_jruby9k_enabled'] = true
        node['classes'].delete('amq::broker')
        reserved_code_cache = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] * ram_per_jruby_code_cache
        settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{reserved_code_cache}m"
        settings['totals']['RAM']['used'] += reserved_code_cache
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

      ram_puppetserver = 1536
      ram_orchestrator = (resources['ram'] * percent_ram_orchestrator).to_i
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 3,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::profile::orchestrator::java_args'                 => { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" },
      }

      total_cpu = params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_puppetserver + ram_orchestrator
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
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
      }
      classes = {
        'database' => true,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => classes }

      ram_database = (resources['ram'] * percent_ram_database).to_i
      ram_puppetdb = (resources['ram'] * percent_ram_puppetdb_split).to_i

      params = {
        'puppet_enterprise::profile::database::shared_buffers'         => "#{ram_database}MB",
        'puppet_enterprise::puppetdb::command_processing_threads'      => 2,
        'puppet_enterprise::profile::puppetdb::java_args'              => { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::database::autovacuum_max_workers' => 3,
        'puppet_enterprise::profile::database::autovacuum_work_mem'    => '341MB',
        'puppet_enterprise::profile::database::maintenance_work_mem'   => '1024MB',
        'puppet_enterprise::profile::database::max_connections'        => 1000,
        'puppet_enterprise::profile::database::work_mem'               => '8MB',
        'puppet_enterprise::profile::database::log_temp_files'         => 8192,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads']
      total_ram = ram_database + ram_puppetdb
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
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
      }
      classes = {
        'database' => false,
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => classes }

      ram_puppetdb = (resources['ram'] * percent_ram_puppetdb_split_external).to_i

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'         => { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" },
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads']
      total_ram = ram_puppetdb
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
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

      ram_puppetserver = 5376
      mb_per_jruby     = 768

      params = {
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 7,
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
      }

      total_cpu = params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_puppetserver
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
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
      }
      node = { 'resources' => resources, 'infrastructure' => infrastructure, 'type' => {}, 'classes' => {} }

      ram_database = 2048

      params = {
        'puppet_enterprise::profile::database::shared_buffers'         => "#{ram_database}MB",
        'puppet_enterprise::profile::database::autovacuum_max_workers' => 3,
        'puppet_enterprise::profile::database::autovacuum_work_mem'    => '341MB',
        'puppet_enterprise::profile::database::maintenance_work_mem'   => '1024MB',
        'puppet_enterprise::profile::database::max_connections'        => 1000,
        'puppet_enterprise::profile::database::work_mem'               => '8MB',
        'puppet_enterprise::profile::database::log_temp_files'         => 8192,
      }

      total_cpu = 0
      total_ram = ram_database
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
      }

      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_database_settings(node)).to eq(settings)
    end
  end

  context 'with a monolithic infrastructure with compilers' do
    it 'can calculate compiler host settings, server size small' do
      resources = {
        'cpu' => 4,
        'ram' => 8192,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
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

      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 1024
      mb_per_jruby     = 512

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 1,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 2,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 2,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 3,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_puppetdb + ram_puppetserver
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate compiler host settings, server size medium' do
      resources = {
        'cpu' => 8,
        'ram' => 16384,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
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

      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 3840
      mb_per_jruby     = 768

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 2,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 5,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 4,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 7,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_puppetdb + ram_puppetserver
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
    end

    it 'can calculate compiler host settings, server size large' do
      resources = {
        'cpu' => 16,
        'ram' => 32768,
      }
      infrastructure = {
        'is_monolithic'        => true,
        'with_compile_masters' => true,
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

      ram_puppetdb     = (resources['ram'] * percent_ram_puppetdb).to_i
      ram_puppetserver = 12288
      mb_per_jruby     = 1024

      params = {
        'puppet_enterprise::puppetdb::command_processing_threads'             => 3,
        'puppet_enterprise::master::puppetserver::jruby_max_active_instances' => 12,
        'puppet_enterprise::profile::puppetdb::java_args'                     => { 'Xms' => "#{ram_puppetdb}m",     'Xmx' => "#{ram_puppetdb}m" },
        'puppet_enterprise::profile::master::java_args'                       => { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" },
        'puppet_enterprise::puppetdb::write_maximum_pool_size'                => 6,
        'puppet_enterprise::puppetdb::read_maximum_pool_size'                 => 18,
        'puppet_enterprise::profile::puppetdb::gc_interval'                   => 0,
      }

      total_cpu = params['puppet_enterprise::puppetdb::command_processing_threads'] +
                  params['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
      total_ram = ram_puppetdb + ram_puppetserver
      totals = {
        'CPU'          => { 'total' => resources['cpu'], 'used' => total_cpu },
        'RAM'          => { 'total' => resources['ram'], 'used' => total_ram },
        'MB_PER_JRUBY' => mb_per_jruby,
      }

      settings = { 'params' => params, 'totals' => totals }

      expect(calculator::calculate_master_settings(node)).to eq(settings)
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
      expect((calculator.send :select_reserved_memory, 4096)).to eq(256)
      expect((calculator.send :select_reserved_memory, 8192)).to eq(512)
      expect((calculator.send :select_reserved_memory, 16384)).to eq(1024)
    end

    it 'can calculate the optional memory reserved for the operating system' do
      calculator.instance_variable_set(:@options, :memory_reserved_for_os => 2048)
      expect((calculator.send :select_reserved_memory, 32768)).to eq(2048)
    end

    it 'can calculate a setting based upon amount of memory' do
      expect((calculator.send :fit_to_memory, 4096,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_memory, 8192,  'S', 'M', 'L')).to eq('S')
      expect((calculator.send :fit_to_memory, 16384, 'S', 'M', 'L')).to eq('M')
      expect((calculator.send :fit_to_memory, 32768, 'S', 'M', 'L')).to eq('L')
      expect((calculator.send :fit_to_memory, 32769, 'S', 'M', 'L')).to eq('L')
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
