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
          @defaults[:compile_time_factor]      = 2

          # Round up when memory is close to the next level of our leveled settings. See fit_to_memory().
          @defaults[:fit_to_memory_percentage] = 5

          # Leave this much memory unallocated for the operating system, and other applications.
          @defaults[:memory_reserved_for_os]   = 1024

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
        # Levels and ratios model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def calculate_master_settings(node)
          percent_ram_database        = 25
          percent_ram_puppetdb        = 10

          percent_cpu_puppetdb        = 25
          percent_cpu_puppetserver    = 75

          minimum_cpu_puppetdb        = 1
          minimum_cpu_puppetserver    = 2

          minimum_ram_puppetserver    = 512

          minimum_ram_code_cache      = 128
          maximum_ram_code_cache      = 2048

          ram_per_jruby               = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          ram_per_jruby_code_cache    = 128

          minimum_ram_database        = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_ram_database        = 16384

          minimum_ram_puppetdb        = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_ram_puppetdb        = 8192

          ram_console                 = fit_to_memory(node['resources']['ram'], 512, 768, 1024)

          ram_orchestrator            = fit_to_memory(node['resources']['ram'], 512, 768, 1024)

          ram_activemq                = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)

          ram_reserved_os             = select_memory_reserved_for_os

          settings = initialize_settings(node)

          # Use the optional value, if defined; or optionally use the currently specified amount of memory_per_jruby.

          if @options[:memory_per_jruby] != 0
            ram_per_jruby = @options[:memory_per_jruby]
          elsif node['current_memory_per_jruby'] && node['current_memory_per_jruby'] != 0
            ram_per_jruby = node['current_memory_per_jruby']
          end

          # Reallocate resources between puppetserver and puppetdb, if this host is a monolithic master or replica master, with compile masters or compilers.

          if node['type']['is_monolithic_master'] || node['type']['is_replica_master']
            if node['infrastructure']['with_compile_masters']
              percent_ram_puppetdb     = 20
              percent_cpu_puppetdb     = 50
              percent_cpu_puppetserver = 33
            end
          end

          # Reallocate resources depending upon PE Infrastructure services on this host.

          percent_cpu_puppetserver = 100 unless node['classes']['puppetdb']

          # Calculate the following maximums after the above reallocations.

          maximum_cpu_puppetserver = [minimum_cpu_puppetserver, (node['resources']['cpu'] * (percent_cpu_puppetserver * 0.01) - 1).to_i].max
          maximum_cpu_puppetdb     = [minimum_cpu_puppetdb, (node['resources']['cpu'] * 0.50).to_i].max

          # Reallocate resources between puppetserver and orchestrator, if this host is running PE 2019.2 or newer.
          # ORCH-2384: Orchestrator in PE 2019.2 has jrubies, and requires (estimated) a processor and additional memory.

          if node['classes']['orchestrator'] && node['type']['with_orchestrator_jruby']
            maximum_cpu_puppetserver = [maximum_cpu_puppetserver - 1, 1].max
            ram_orchestrator += ram_per_jruby
          end

          # The Vegas Renormalization: allow for testing with vmpooler (2 CPU / 6 GB RAM) VMs.
          # Setting minimum_cpu_puppetserver to 1 as a default above results in an unused core when CPU equals 3 or 4.

          if node['resources']['cpu'] < 3
            minimum_cpu_puppetserver = 1
            maximum_cpu_puppetserver = 1
          end

          # Do not allocate memory for reserved_code_cache for depending upon JRuby version.

          ram_per_jruby_code_cache = 0 unless node['type']['with_jruby9k_enabled']

          # Allocate processors and memory for PE Infrastructure services ...

          if node['classes']['database']
            ram_database = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_database, minimum_ram_database, maximum_ram_database)
            unless ram_database
              Puppet.debug("Error: unable to calculate ram_database")
              return
            end
            settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
            settings['totals']['RAM']['used'] += ram_database
          end

          if node['classes']['puppetdb']

            # Reallocate resources between puppetserver and puppetdb, if this host is a compiler (puppetserver plus puppetdb).

            if node['type']['is_compile_master'] || node['type']['is_compiler']
              percent_cpu_puppetdb = 25
              minimum_cpu_puppetdb = 1
              maximum_cpu_puppetdb = 3
            end

            command_processing_threads = calculate_cpu(node['resources']['cpu'], settings['totals']['CPU']['used'], percent_cpu_puppetdb, minimum_cpu_puppetdb, maximum_cpu_puppetdb)
            unless command_processing_threads
              Puppet.debug("Error: unable to calculate command_processing_threads")
              return
            end
            settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
            settings['totals']['CPU']['used'] += command_processing_threads

            ram_puppetdb = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_puppetdb, minimum_ram_puppetdb, maximum_ram_puppetdb)
            unless ram_puppetdb
              Puppet.debug("Error: unable to calculate ram_puppetdb")
              return
            end
            settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
            settings['totals']['RAM']['used'] += ram_puppetdb
          end

          if node['classes']['console']
            settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
            settings['totals']['RAM']['used'] += ram_console
          end

          if node['classes']['orchestrator']
            settings['params']['puppet_enterprise::profile::orchestrator::java_args'] = { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" }
            settings['totals']['RAM']['used'] += ram_orchestrator
            if node['type']['with_orchestrator_jruby']
              # ORCH-2384:
              #
              # minimum_cpu_orchestrator = 1
              # maximum_cpu_orchestrator = 1
              # max_jrubies_in_ram_orchestrator = (ram_orchestrator / (ram_per_jruby + ram_per_jruby_code_cache)).to_i
              # orchestrator_jruby_max_active_instances = max_jrubies_in_ram_orchestrator.clamp(minimum_cpu_orchestrator, maximum_cpu_orchestrator)
              # settings['params']['puppet_enterprise::master::orchestrator::jruby_max_active_instances'] = orchestrator_jruby_max_active_instances
              # settings['totals']['CPU']['used'] += orchestrator_jruby_max_active_instances
              #
              # orchestrator_code_cache_based_upon_jrubies = orchestrator_jruby_max_active_instances * ram_per_jruby_code_cache
              # ram_orchestrator_code_cache = orchestrator_code_cache_based_upon_jrubies.clamp(minimum_ram_code_cache, maximum_ram_code_cache)
              # settings['params']['puppet_enterprise::master::orchestrator::reserved_code_cache'] = "#{ram_orchestrator_code_cache}m"
              # settings['totals']['RAM']['used'] += ram_orchestrator_code_cache
            end
          end

          if node['classes']['amq::broker']
            settings['params']['puppet_enterprise::profile::amq::broker::heap_mb'] = ram_activemq
            settings['totals']['RAM']['used'] += ram_activemq
          end

          ram_puppetserver = node['resources']['ram'] - ram_reserved_os - settings['totals']['RAM']['used']
          if ram_puppetserver < minimum_ram_puppetserver
            Puppet.debug("Error: ram_puppetserver: #{ram_puppetserver} MB is less than minimum_ram_puppetserver: #{minimum_ram_puppetserver} MB")
            return
          end

          max_jrubies_in_ram_puppetserver = (ram_puppetserver / (ram_per_jruby + ram_per_jruby_code_cache)).to_i
          puppetserver_jruby_max_active_instances = max_jrubies_in_ram_puppetserver.clamp(minimum_cpu_puppetserver, maximum_cpu_puppetserver)
          settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] = puppetserver_jruby_max_active_instances
          settings['totals']['CPU']['used'] += puppetserver_jruby_max_active_instances

          ram_puppetserver = [(puppetserver_jruby_max_active_instances * ram_per_jruby), minimum_ram_puppetserver].max
          settings['params']['puppet_enterprise::profile::master::java_args'] = { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" }
          settings['totals']['RAM']['used'] += ram_puppetserver

          if node['type']['with_jruby9k_enabled']
            code_cache_based_upon_jrubies = puppetserver_jruby_max_active_instances * ram_per_jruby_code_cache
            ram_puppetserver_code_cache = code_cache_based_upon_jrubies.clamp(minimum_ram_code_cache, maximum_ram_code_cache)
            settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{ram_puppetserver_code_cache}m"
            settings['totals']['RAM']['used'] += ram_puppetserver_code_cache
          end

          settings['totals']['MB_PER_JRUBY'] = ram_per_jruby

          # Reallocate resources from puppetdb to avoid making too many connections to databases, if this host is a compiler (puppetserver plus puppetdb).

          if node['classes']['puppetdb'] && (node['type']['is_compile_master'] || node['type']['is_compiler'])
            read_maximum_pool_size  = puppetserver_jruby_max_active_instances + [(puppetserver_jruby_max_active_instances / 2).to_i, 1].max
            write_maximum_pool_size = (command_processing_threads * 2)
            settings['params']['puppet_enterprise::puppetdb::read_maximum_pool_size'] = read_maximum_pool_size
            settings['params']['puppet_enterprise::puppetdb::write_maximum_pool_size'] = write_maximum_pool_size
            settings['params']['puppet_enterprise::profile::puppetdb::gc_interval'] = 0
          end

          settings
        end

        # Console Hosts in Split Infrastructures
        # Services: pe-console-services

        def calculate_console_settings(node)
          percent_ram_console = 75

          minimum_ram_console = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          maximum_ram_console = 4096

          settings = initialize_settings(node)

          ram_console = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_console, minimum_ram_console, maximum_ram_console)
          unless ram_console
            Puppet.debug("Error: unable to calculate ram_console")
            return
          end
          settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
          settings['totals']['RAM']['used'] += ram_console

          settings
        end

        # PuppetDB Hosts in Split Infrastructures
        # Services: pe-puppetdb and (by default, but optionally) pe-postgresql

        def calculate_puppetdb_settings(node)
          percent_cpu_puppetdb = 50

          minimum_cpu_puppetdb = 1
          maximum_cpu_puppetdb = [minimum_cpu_puppetdb, (node['resources']['cpu'] * (percent_cpu_puppetdb * 0.01)).to_i].max

          percent_ram_puppetdb = 50

          minimum_ram_puppetdb = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_ram_puppetdb = 8192

          settings = initialize_settings(node)

          if node['classes']['database']
            percent_ram_puppetdb = 25
            database_settings = calculate_database_settings(node)
            return unless database_settings
            settings['params'].merge!(database_settings['params'])
            settings['totals']['CPU']['used'] += database_settings['totals']['CPU']['used']
            settings['totals']['RAM']['used'] += database_settings['totals']['RAM']['used']
          end

          command_processing_threads = calculate_cpu(node['resources']['cpu'], settings['totals']['CPU']['used'], percent_cpu_puppetdb, minimum_cpu_puppetdb, maximum_cpu_puppetdb)
          unless command_processing_threads
            Puppet.debug("Error: unable to calculate command_processing_threads")
            return
          end
          settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
          settings['totals']['CPU']['used'] += command_processing_threads

          ram_puppetdb = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_puppetdb, minimum_ram_puppetdb, maximum_ram_puppetdb)
          unless ram_puppetdb
            Puppet.debug("Error: unable to calculate ram_puppetdb")
            return
          end
          settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
          settings['totals']['RAM']['used'] += ram_puppetdb

          settings
        end

        # External PostgreSQL Hosts in Monolithic and/or PuppetDB Hosts in Split Infrastructures
        # Services: pe-postgresql

        def calculate_database_settings(node)
          percent_ram_database               = 25

          minimum_ram_database               = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_ram_database               = 16384

          percent_cpu_autovacuum_max_workers = 33.3
          minimum_cpu_autovacuum_max_workers = 3
          maximum_cpu_autovacuum_max_workers = 8

          maintenance_work_mem_divisor       = 3.0 # Divide by 3 if External or Split, as opposed to 8 if Monolithic.

          maximum_ram_maintenance_work_mem   = 1024

          double_default_max_connections     = 1000
          double_default_work_mem            = 8

          settings = initialize_settings(node)

          ram_database = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_database, minimum_ram_database, maximum_ram_database)
          unless ram_database
            Puppet.debug("Error: unable to calculate ram_database")
            return
          end
          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
          settings['totals']['RAM']['used'] += ram_database

          cpu_autovacuum_max_workers = percent_clamp(percent_cpu_autovacuum_max_workers, maximum_cpu_autovacuum_max_workers, minimum_cpu_autovacuum_max_workers, maximum_cpu_autovacuum_max_workers)
          ram_maintenance_work_mem   = [maximum_ram_maintenance_work_mem, (node['resources']['ram'] / maintenance_work_mem_divisor).to_i].min
          ram_autovacuum_work_mem    = (ram_maintenance_work_mem / cpu_autovacuum_max_workers).to_i

          # The following settings are not steady-state allocations, so are not added to settings['totals'].

          settings['params']['puppet_enterprise::profile::database::autovacuum_max_workers'] = cpu_autovacuum_max_workers
          settings['params']['puppet_enterprise::profile::database::autovacuum_work_mem']    = "#{ram_autovacuum_work_mem}MB"
          settings['params']['puppet_enterprise::profile::database::maintenance_work_mem']   = "#{ram_maintenance_work_mem}MB"
          settings['params']['puppet_enterprise::profile::database::max_connections']        = double_default_max_connections
          settings['params']['puppet_enterprise::profile::database::work_mem']               = "#{double_default_work_mem}MB"
          settings['params']['puppet_enterprise::profile::database::log_temp_files']         = double_default_work_mem * 1024

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

        def select_memory_reserved_for_os
          (@options[:memory_reserved_for_os] != 0) ? @options[:memory_reserved_for_os] : @defaults[:memory_reserved_for_os]
        end

        # Return a value within a minimum and maximum amount of available processors.

        def calculate_cpu(total, used, percent, minimum, maximum)
          available = total - used
          if available < minimum
            Puppet.debug("Error: available processors: #{available} is less than minimum processors: #{minimum}")
            return
          end
          percent_clamp(percent, available, minimum, maximum)
        end

        # Return a value within a minimum and maximum amount of available (minus memory_reserved_for_os) memory.

        def calculate_ram(total, used, percent, minimum, maximum)
          reserved  = select_memory_reserved_for_os
          available = total - reserved - used
          if available < minimum
            Puppet.debug("Error: available memory: #{available} is less than minimum memory: #{minimum}")
            return
          end
          percent_clamp(percent, available, minimum, maximum)
        end

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_processors(processors, small, medium, large)
          return small  if processors <= 4
          return medium if processors <= 8
          return medium if processors <  16
          Puppet.debug('Using a maximum value for fit_to_processors')
          return large  if processors >= 16
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

        # Return a percentage of a value or the minimum or maximum, with minimum having a higher precedence than maximum.

        def percent_clamp(percent, value, minimum, maximum)
          value = (value * percent * 0.01).to_i
          value.clamp(minimum, maximum)
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
