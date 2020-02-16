# Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current, or calculate optimized settings.
    class Tune
      # Calculate optimized settings.
      class Calculate
        # Calculon Compute!

        def initialize(options)
          @defaults = {}

          # For use when estimating capacity.
          @defaults[:compile_time_factor] = 2

          # Round up when memory is close to the next level of our leveled settings. See fit_to_memory().
          @defaults[:fit_to_memory_percentage] = 5

          # Memory reserved for the operating system (and other applications).
          @defaults[:memory_reserved_for_os_percentage] = 0.25

          @options = {}

          # Users may override these defaults via command line options.
          @options[:memory_per_jruby]       = options[:memory_per_jruby] || 0
          @options[:memory_reserved_for_os] = options[:memory_reserved_for_os] || 0

          Puppet.debug("Using optional #{@options[:memory_per_jruby]} MB RAM per JRuby") if @options[:memory_per_jruby] != 0
          Puppet.debug("Using optional #{@options[:memory_reserved_for_os]} MB RAM reserved for the operating system") if @options[:memory_reserved_for_os] != 0
        end

        #
        # PE Infrastructure Roles
        #

        # Masters, Replicas, and Compilers, in Monolithic or Split Infrastructures
        # Services: pe-puppetserver and (optionally) all other services.
        # Ratios model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def calculate_master_settings(node)
          percent_cpu_puppetdb     = 0.25
          minimum_cpu_puppetdb     = 1
          maximum_cpu_puppetdb     = (node['resources']['cpu'] * 0.50).to_i

          minimum_cpu_orchestrator = 1
          maximum_cpu_orchestrator = 4

          minimum_cpu_puppetserver = 2
          maximum_cpu_puppetserver = 24

          percent_ram_database     = 0.20
          percent_ram_puppetdb     = 0.10
          percent_ram_orchestrator = 0.08
          percent_ram_console      = 0.08
          percent_ram_activemq     = 0.08

          minimum_ram_puppetserver = 512

          minimum_ram_code_cache   = 96
          maximum_ram_code_cache   = 2048

          minimum_ram_database     = 1
          maximum_ram_database     = 16384

          minimum_ram_puppetdb     = 512
          maximum_ram_puppetdb     = 8192

          minimum_ram_orchestrator = 512
          maximum_ram_orchestrator = 1024

          minimum_ram_console      = 512
          maximum_ram_console      = 1024

          minimum_ram_activemq     = 256
          maximum_ram_activemq     = 512

          ram_per_jruby            = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          ram_per_jruby_code_cache = 96

          cpu_reserved             = 1
          ram_reserved             = select_reserved_memory(node['resources']['ram'])

          # https://github.com/puppetlabs/puppet-enterprise-modules/blob/irving/modules/puppet_enterprise/manifests/profile/database.pp
          default_database_max_connections = 400

          percent_database_connections = 1.10

          settings = initialize_settings(node)

          # Optionally use memory_per_jruby, if defined.

          ram_per_jruby = @options[:memory_per_jruby] if @options[:memory_per_jruby] != 0

          # Optionally use current_memory_per_jruby, if defined.

          ram_per_jruby = node['current_memory_per_jruby'] if node['current_memory_per_jruby'] && node['current_memory_per_jruby'] != 0

          # Reallocate resources between puppetserver and puppetdb, if this host is a monolithic master or replica master, with compile masters or compilers.

          if node['type']['is_monolithic_master'] || node['type']['is_replica_master']
            if node['infrastructure']['with_compile_masters']
              percent_cpu_puppetdb     = 0.50
              percent_ram_puppetdb     = 0.15
            end
          end

          # The Vegas Renormalization: allow for testing with vmpooler (2 CPU / 6 GB RAM) VMs.

          if node['resources']['cpu'] < 3
            minimum_cpu_puppetserver = 1
            maximum_cpu_puppetserver = 1
            cpu_reserved             = 1
            ram_reserved             = 256
          end

          # Do not allocate memory for reserved_code_cache, depending upon jruby version.

          unless node['type']['with_jruby9k_enabled']
            minimum_ram_code_cache   = 0
            ram_per_jruby_code_cache = 0
          end

          # Allocate processors and memory for PE Infrastructure services ...

          if node['classes']['database']
            ram_database = (node['resources']['ram'] * percent_ram_database).to_i.clamp(minimum_ram_database, maximum_ram_database)
            settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
            settings['totals']['RAM']['used'] += ram_database
          end

          if node['classes']['puppetdb']
            # Reallocate resources between puppetserver and puppetdb, if this host is a compiler (puppetserver plus puppetdb).
            if node['type']['is_compile_master'] || node['type']['is_compiler']
              percent_cpu_puppetdb = 0.25
              minimum_cpu_puppetdb = 1
              maximum_cpu_puppetdb = 3
            end

            command_processing_threads = (node['resources']['cpu'] * percent_cpu_puppetdb).to_i.clamp(minimum_cpu_puppetdb, maximum_cpu_puppetdb)
            settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
            settings['totals']['CPU']['used'] += command_processing_threads

            ram_puppetdb = (node['resources']['ram'] * percent_ram_puppetdb).to_i.clamp(minimum_ram_puppetdb, maximum_ram_puppetdb)
            settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
            settings['totals']['RAM']['used'] += ram_puppetdb
          end

          if node['classes']['orchestrator']
            if node['type']['with_orchestrator_jruby']
              # Reallocate resources between orchestrator and puppetserver, if orchestrator has jrubies.
              percent_ram_orchestrator = 0.10

              # Note: orchestrator_jruby_max_active_instances is constrained based on how many jrubies fit into orchestrator memory.
              ram_orchestrator = [(node['resources']['ram'] * percent_ram_orchestrator).to_i, minimum_ram_orchestrator].max
              max_jrubies_in_ram_orchestrator = (ram_orchestrator / ram_per_jruby).to_i
              orchestrator_jruby_max_active_instances = max_jrubies_in_ram_orchestrator.clamp(minimum_cpu_orchestrator, maximum_cpu_orchestrator)
              settings['params']['puppet_enterprise::profile::orchestrator::jruby_max_active_instances'] = orchestrator_jruby_max_active_instances
              # Note: orchestrator_jruby_max_active_instances is not a dedicated allocation, do not add it to settings['totals']['CPU']['used'].

              # ram_orchestrator_code_cache = orchestrator_jruby_max_active_instances * ram_per_jruby_code_cache
              # settings['params']['puppet_enterprise::profile::orchestrator::reserved_code_cache'] = ram_orchestrator_code_cache
              # settings['totals']['RAM']['used'] += ram_orchestrator_code_cache
            else
              ram_orchestrator = (node['resources']['ram'] * percent_ram_orchestrator).to_i.clamp(minimum_ram_orchestrator, maximum_ram_orchestrator)
            end
            settings['params']['puppet_enterprise::profile::orchestrator::java_args'] = { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" }
            settings['totals']['RAM']['used'] += ram_orchestrator
          end

          if node['classes']['console']
            ram_console = (node['resources']['ram'] * percent_ram_console).to_i.clamp(minimum_ram_console, maximum_ram_console)
            settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
            settings['totals']['RAM']['used'] += ram_console
          end

          if node['classes']['amq::broker']
            ram_activemq = (node['resources']['ram'] * percent_ram_activemq).to_i.clamp(minimum_ram_activemq, maximum_ram_activemq)
            settings['params']['puppet_enterprise::profile::amq::broker::heap_mb'] = ram_activemq
            settings['totals']['RAM']['used'] += ram_activemq
          end

          # Note: puppetserver is not allocated a percentage of memory: it is initially allocated all unused memory.

          ram_puppetserver = (node['resources']['ram'] - ram_reserved - settings['totals']['RAM']['used'])
          if ram_puppetserver < (minimum_ram_puppetserver + minimum_ram_code_cache)
            Puppet.debug("Error: available memory for puppetserver: #{ram_puppetserver} MB is less than minimum required: #{minimum_ram_puppetserver} + #{minimum_ram_code_cache} MB")
            return
          end

          # Note: puppetserver_jruby_max_active_instances is constrained based on both how many jrubies fit into unallocated memory and unallocated processors.

          maximum_cpu_puppetserver = (node['resources']['cpu'] - cpu_reserved - settings['totals']['CPU']['used']).clamp(minimum_cpu_puppetserver, maximum_cpu_puppetserver)
          max_jrubies_in_ram_puppetserver = (ram_puppetserver / (ram_per_jruby + ram_per_jruby_code_cache)).to_i
          puppetserver_jruby_max_active_instances = max_jrubies_in_ram_puppetserver.clamp(minimum_cpu_puppetserver, maximum_cpu_puppetserver)
          settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] = puppetserver_jruby_max_active_instances
          settings['totals']['CPU']['used'] += puppetserver_jruby_max_active_instances

          ram_puppetserver = [minimum_ram_puppetserver, (puppetserver_jruby_max_active_instances * ram_per_jruby)].max
          settings['params']['puppet_enterprise::profile::master::java_args'] = { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" }
          settings['totals']['RAM']['used'] += ram_puppetserver

          if node['type']['with_jruby9k_enabled']
            code_cache_based_upon_jrubies = puppetserver_jruby_max_active_instances * ram_per_jruby_code_cache
            ram_puppetserver_code_cache = code_cache_based_upon_jrubies.clamp(minimum_ram_code_cache, maximum_ram_code_cache)
            settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{ram_puppetserver_code_cache}m"
            settings['totals']['RAM']['used'] += ram_puppetserver_code_cache
          end

          settings['totals']['MB_PER_JRUBY'] = ram_per_jruby

          # Detune puppetdb to avoid making too many connections to the database and disable garbage collection, if this host is a compiler (puppetserver with puppetdb).

          if node['classes']['puppetdb'] && (node['type']['is_compile_master'] || node['type']['is_compiler'])
            read_maximum_pool_size  = puppetserver_jruby_max_active_instances + [1, (puppetserver_jruby_max_active_instances / 2).to_i].max
            write_maximum_pool_size = (command_processing_threads * 2)
            settings['params']['puppet_enterprise::puppetdb::read_maximum_pool_size'] = read_maximum_pool_size
            settings['params']['puppet_enterprise::puppetdb::write_maximum_pool_size'] = write_maximum_pool_size
            settings['params']['puppet_enterprise::profile::puppetdb::gc_interval'] = 0
          end

          # Increase max_connections when the potential number of connections from compilers exceeds the default.

          if node['classes']['database'] && node['infrastructure']['compiler_connections']
            if node['infrastructure']['compiler_connections'] > default_database_max_connections
              settings['params']['puppet_enterprise::profile::database::max_connections'] = (node['infrastructure']['compiler_connections'] * percent_database_connections).to_i
            end
          end

          # Do not return any settings when overallocating.

          if settings['totals']['CPU']['used'] > settings['totals']['CPU']['total']
            Puppet.debug("Error: calculations overallocated processors: #{settings}")
            return
          end
          if (settings['totals']['RAM']['used'] + ram_reserved) > settings['totals']['RAM']['total']
            Puppet.debug("Error: calculations overallocated memory: reserved: #{ram_reserved} settings: #{settings}")
            return
          end

          settings
        end

        # Console Hosts in Split Infrastructures
        # Services: pe-console-services

        def calculate_console_settings(node)
          percent_ram_console = 0.75
          minimum_ram_console = 512
          maximum_ram_console = 4096

          # Unused here, as this role is deprecated.
          # ram_reserved = select_reserved_memory(node['resources']['ram'])

          settings = initialize_settings(node)

          ram_console = (node['resources']['ram'] * percent_ram_console).to_i.clamp(minimum_ram_console, maximum_ram_console)
          settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
          settings['totals']['RAM']['used'] += ram_console

          settings
        end

        # PuppetDB Hosts in Split Infrastructures
        # Services: pe-puppetdb and (by default, but optionally) pe-postgresql

        def calculate_puppetdb_settings(node)
          percent_cpu_puppetdb = 0.50
          minimum_cpu_puppetdb = 1
          maximum_cpu_puppetdb = (node['resources']['cpu'] * percent_cpu_puppetdb).to_i

          percent_ram_puppetdb = 0.50
          minimum_ram_puppetdb = 512
          maximum_ram_puppetdb = 8192

          # Unused here, as this role is deprecated.
          # ram_reserved = select_reserved_memory(node['resources']['ram'])

          settings = initialize_settings(node)

          if node['classes']['database']
            percent_ram_puppetdb = 0.25
            database_settings = calculate_database_settings(node)
            settings['params'].merge!(database_settings['params'])
            settings['totals']['CPU']['used'] += database_settings['totals']['CPU']['used']
            settings['totals']['RAM']['used'] += database_settings['totals']['RAM']['used']
          end

          command_processing_threads = [minimum_cpu_puppetdb, maximum_cpu_puppetdb].max
          settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
          settings['totals']['CPU']['used'] += command_processing_threads

          ram_puppetdb = (node['resources']['ram'] * percent_ram_puppetdb).to_i.clamp(minimum_ram_puppetdb, maximum_ram_puppetdb)
          settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
          settings['totals']['RAM']['used'] += ram_puppetdb

          settings
        end

        # External PostgreSQL Hosts in Monolithic and/or PuppetDB Hosts in Split Infrastructures
        # Services: pe-postgresql

        def calculate_database_settings(node)
          percent_ram_database               = 0.20
          minimum_ram_database               = 2048
          maximum_ram_database               = 16384

          ram_reserved                       = select_reserved_memory(node['resources']['ram'])

          # https://github.com/puppetlabs/puppet-enterprise-modules/blob/irving/modules/puppet_enterprise/manifests/profile/database.pp
          default_database_max_connections = 400

          percent_database_connections = 1.10

          settings = initialize_settings(node)

          ram_database = ((node['resources']['ram'] - ram_reserved) * percent_ram_database).to_i.clamp(minimum_ram_database, maximum_ram_database)
          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
          settings['totals']['RAM']['used'] += ram_database

          # Increase max_connections when the potential number of connections from compilers exceeds the default.

          if node['infrastructure']['compiler_connections']
            if node['infrastructure']['compiler_connections'] > default_database_max_connections
              settings['params']['puppet_enterprise::profile::database::max_connections'] = (node['infrastructure']['compiler_connections'] * percent_database_connections).to_i
            end
          end

          settings
        end

        # Return a new settings structure.

        def initialize_settings(node)
          {
            'params' => {},
            'totals' => {
              'CPU' => { 'total' => node['resources']['cpu'], 'used' => 0 },
              'RAM' => { 'total' => node['resources']['ram'], 'used' => 0 },
            },
          }
        end

        #
        # Utilities
        #

        # Estimate a reasonable sample of agent runs based upon node count and run interval.

        def calculate_run_sample(active_nodes, run_interval)
          maximum = 10000
          seconds_per_day = 86400
          # If running continuously ...
          return [active_nodes, maximum].min if run_interval.zero?
          runs_per_day = (seconds_per_day / run_interval).to_i
          # If running less than once per day ...
          return [active_nodes * 7, maximum].min if runs_per_day < 1
          [active_nodes * runs_per_day, maximum].min
        end

        # Little's Law
        #
        #   L = λ * W
        #
        # Where:
        #
        #   L = Number of requests in the queue.
        #   λ = Average effective arrival rate of requests.
        #   W = Average time spent processing a request.

        # Estimate the theoretical maximum number of nodes that can managed by an infrastructure.

        def calculate_maximum_nodes(average_compile_time, available_jrubies, run_interval)
          jruby_lock_time = average_compile_time.to_f * @defaults[:compile_time_factor]
          ((run_interval.to_f * available_jrubies.to_f) / jruby_lock_time.to_f).ceil
        end

        # Estimate the theoretical minimum number of jrubies required to manage an infrastructure.

        def calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
          jruby_lock_time = average_compile_time.to_f * @defaults[:compile_time_factor]
          ((active_nodes.to_f * jruby_lock_time.to_f) / run_interval.to_f).ceil
        end

        # Return the option or the default.

        def select_reserved_memory(memory)
          return @options[:memory_reserved_for_os] if @options[:memory_reserved_for_os] != 0
          (memory * @defaults[:memory_reserved_for_os_percentage]).to_i
        end

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_memory(memory, small, medium, large)
          # Round up to the nearest power of two (31500 -> 32768) if within a percentage.
          target_memory = nearest_power_of_two(memory)
          if (memory < target_memory) && within_percent?(memory, target_memory, @defaults[:fit_to_memory_percentage])
            Puppet.debug("Rounding #{memory} up to #{target_memory} for fit_to_memory")
            memory = target_memory
          end
          return small  if memory <= 8192
          return medium if memory <= 16384
          return medium if memory <  32768
          Puppet.debug('Using a maximum value for fit_to_memory')
          return large  if memory >= 32768
        end

        # Test if a number is within a percentage of another number.

        def within_percent?(actual, target, percentage)
          return false if actual == target
          (Float(target - actual) / target * 100).ceil <= percentage
        end

        # Return a number as a computer-science number.

        def nearest_power_of_two(number)
          return 0 if number <= 0
          exponent = Math.log2 number
          higher_power = 2**exponent.ceil
          lower_power  = 2**exponent.floor
          ((higher_power - number) <= (number - lower_power)) ? higher_power : lower_power
        end
      end
    end
  end
end
