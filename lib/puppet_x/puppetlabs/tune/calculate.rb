# Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Calculate optimized settings.
      class Calculate
        # Calculon Compute!

        def initialize(options)
          @defaults = {}
          @defaults[:compile_time_factor]      = 2
          @defaults[:fit_to_memory_percentage] = 5
          @defaults[:memory_reserved_for_os]   = 1024

          @options = {}
          @options[:memory_per_jruby]       = options[:memory_per_jruby] || 0
          @options[:memory_reserved_for_os] = options[:memory_reserved_for_os] || 0

          Puppet.debug("Using optional %{mem}MB RAM per JRuby") % { mem: @options[:memory_per_jruby] } if @options[:memory_per_jruby] != 0
          Puppet.debug("Using optional %{mem}MB RAM reserved for the operating system") % { mem: @options[:memory_reserved_for_os] } if @options[:memory_reserved_for_os] != 0
        end

        #
        # Roles
        #

        # Masters and Compile Masters in Monolithic or Split Infrastructures
        # Services: pe-puppetserver and (optionally) all other services

        def calculate_master_settings(node)
          percent_cpu_threads         = 25
          minimum_cpu_threads         = fit_to_processors(node['resources']['cpu'], 1, 2, 4)
          percent_cpu_jrubies         = 75
          minimum_cpu_jrubies         = 2
          minimum_ram_puppetserver    = 1024
          ram_per_puppetserver_jruby  = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          ram_puppetserver_code_cache = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          percent_ram_database        = 25
          minimum_ram_database        = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_ram_database        = 16384
          percent_ram_puppetdb        = 10
          minimum_ram_puppetdb        = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_ram_puppetdb        = 8192
          ram_console                 = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          ram_orchestrator            = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          ram_activemq                = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          ram_per_puppetserver_jruby  = @options[:memory_per_jruby] if @options[:memory_per_jruby] != 0
          minimum_ram_os              = memory_reserved_for_os

          # Reallocate resources depending upon infrastructure.

          if node['type']['is_monolithic_master'] || node['type']['is_replica_master']
            if node['infrastructure']['with_compile_masters']
              # Reallocate resources between puppetserver and puppetdb, if this host is a monolithic master or replica master with compile masters.
              percent_cpu_threads      = 50
              percent_cpu_jrubies      = 33
              percent_ram_puppetdb     = 20
              minimum_ram_puppetserver = 1024
            end
          else
            # Decrease minimum memory allocation for puppetserver, if this host is not a monolithic master or replica master with compile masters.
            minimum_ram_puppetserver = 1024
          end

          ram_puppetserver_code_cache = 0 unless node['type']['with_jruby9k_enabled']

          # Reallocate resources depending upon services active on this host.

          percent_cpu_jrubies         = 100 unless node['classes']['puppetdb']
          percent_cpu_threads         = 0   unless node['classes']['puppetdb']
          minimum_ram_database        = 0   unless node['classes']['database']
          ram_console                 = 0   unless node['classes']['console']
          ram_orchestrator            = 0   unless node['classes']['orchestrator']
          ram_activemq                = 0   unless node['classes']['amq::broker']

          # Calculate the following maximums after the above reallocations.

          maximum_cpu_threads = [minimum_cpu_threads, (node['resources']['cpu'] * (percent_cpu_threads * 0.01)).to_i].max
          maximum_cpu_jrubies = [minimum_cpu_jrubies, (node['resources']['cpu'] * (percent_cpu_jrubies * 0.01) - 1).to_i].max

          # Decrease maximum_cpu_threads on compile masters, if this is an extra large reference architecture, to avoid making too many connections to the external database:

          if node['type']['is_compile_master'] && node['infrastructure']['with_extra_large']
            maximum_cpu_threads = 2
            # puppet_enterprise::puppetdb::write_maximum_pool_size: 4
            # puppet_enterprise::puppetdb::read_maximum_pool_size: 10
          end

          # The Vegas Renormalization: allow for testing with vmpooler (2 CPU / 6 GB RAM) VMs.
          # Requires use of TEST_CPU=8 and TEST_RAM=16384, or the '--force' option.

          if node['resources']['cpu'] < 4
            minimum_cpu_threads = 1
            maximum_cpu_threads = 1
            minimum_cpu_jrubies = 1
            maximum_cpu_jrubies = 1
          end

          if node['resources']['ram'] < 8096
            minimum_ram_database        = 256
            maximum_ram_database        = 256
            minimum_ram_puppetdb        = 256
            maximum_ram_puppetdb        = 256
            ram_puppetserver_code_cache = 256
            minimum_ram_puppetserver    = 256
            ram_per_puppetserver_jruby  = 256
            ram_console                 = 256
            ram_orchestrator            = 256
            ram_activemq                = 256
          end

          settings = initialize_settings(node)

          if node['classes']['database']
            ram_database = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_database, minimum_ram_database, maximum_ram_database)
            return unless ram_database
            settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
            settings['totals']['RAM']['used'] += ram_database
          end

          if node['classes']['puppetdb']
            command_processing_threads = calculate_cpu(node['resources']['cpu'], settings['totals']['CPU']['used'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
            return unless command_processing_threads
            settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
            settings['totals']['CPU']['used'] += command_processing_threads

            ram_puppetdb = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_puppetdb, minimum_ram_puppetdb, maximum_ram_puppetdb)
            return unless ram_puppetdb
            settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
            settings['totals']['RAM']['used'] += ram_puppetdb
          end

          available_ram_for_puppetserver = node['resources']['ram'] - minimum_ram_os - settings['totals']['RAM']['used']
          if available_ram_for_puppetserver < minimum_ram_puppetserver
            Puppet.debug _("Error: available_ram_for_puppetserver: %{available} < minimum_ram_puppetserver: %{minimum}") % { available: available_ram_for_puppetserver, minimum: minimum_ram_puppetserver }
            return {}
          end

          puppetserver_ram_by_ram_per_jruby = (available_ram_for_puppetserver / ram_per_puppetserver_jruby).to_i
          jruby_max_active_instances = value_within_min_max(puppetserver_ram_by_ram_per_jruby, minimum_cpu_jrubies, maximum_cpu_jrubies)
          settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] = jruby_max_active_instances
          settings['totals']['CPU']['used'] += jruby_max_active_instances

          ram_jrubies = (jruby_max_active_instances * ram_per_puppetserver_jruby)
          ram_puppetserver = [ram_jrubies, minimum_ram_puppetserver].max
          settings['params']['puppet_enterprise::profile::master::java_args'] = { 'Xms' => "#{ram_puppetserver}m", 'Xmx' => "#{ram_puppetserver}m" }
          settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{ram_puppetserver_code_cache}m" if ram_puppetserver_code_cache > 0
          settings['totals']['RAM']['used'] += ram_puppetserver + ram_puppetserver_code_cache

          if node['classes']['console']
            settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
            settings['totals']['RAM']['used'] += ram_console
          end

          if node['classes']['orchestrator']
            settings['params']['puppet_enterprise::profile::orchestrator::java_args'] = { 'Xms' => "#{ram_orchestrator}m", 'Xmx' => "#{ram_orchestrator}m" }
            settings['totals']['RAM']['used'] += ram_orchestrator
          end

          if node['classes']['amq::broker']
            settings['params']['puppet_enterprise::profile::amq::broker::heap_mb'] = ram_activemq
            settings['totals']['RAM']['used'] += ram_activemq
          end

          settings['totals']['MB_PER_JRUBY'] = ram_per_puppetserver_jruby

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
          return unless ram_console
          settings['params']['puppet_enterprise::profile::console::java_args'] = { 'Xms' => "#{ram_console}m", 'Xmx' => "#{ram_console}m" }
          settings['totals']['RAM']['used'] += ram_console

          settings
        end

        # PuppetDB Hosts in Split Infrastructures
        # Services: pe-puppetdb and (by default, but optionally) pe-postgresql

        def calculate_puppetdb_settings(node)
          percent_cpu_threads  = 50
          minimum_cpu_threads  = 1
          maximum_cpu_threads  = [minimum_cpu_threads, (node['resources']['cpu'] * (percent_cpu_threads * 0.01)).to_i].max
          percent_ram_puppetdb = 50
          minimum_ram_puppetdb = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_ram_puppetdb = 8192

          settings = initialize_settings(node)

          if node['classes']['database']
            percent_ram_puppetdb = 25
            database_settings = calculate_database_settings(node)
            settings['params'].merge!(database_settings['params'])
            settings['totals']['CPU']['used'] += database_settings['totals']['CPU']['used']
            settings['totals']['RAM']['used'] += database_settings['totals']['RAM']['used']
          end

          command_processing_threads = calculate_cpu(node['resources']['cpu'], settings['totals']['CPU']['used'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
          return unless command_processing_threads
          settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
          settings['totals']['CPU']['used'] += command_processing_threads

          ram_puppetdb = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_puppetdb, minimum_ram_puppetdb, maximum_ram_puppetdb)
          return unless ram_puppetdb
          settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = { 'Xms' => "#{ram_puppetdb}m", 'Xmx' => "#{ram_puppetdb}m" }
          settings['totals']['RAM']['used'] += ram_puppetdb

          settings
        end

        # External PostgreSQL Hosts in Monolithic and Split Infrastructures
        # Services: pe-postgresql

        def calculate_database_settings(node)
          percent_ram_database    = 25
          minimum_ram_database    = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_ram_database    = 16384
          default_max_connections = 500

          settings = initialize_settings(node)

          ram_database = calculate_ram(node['resources']['ram'], settings['totals']['RAM']['used'], percent_ram_database, minimum_ram_database, maximum_ram_database)
          return unless ram_database
          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
          settings['totals']['RAM']['used'] += ram_database

          # Increase max_connections for postgresql, if this is an extra large reference architecture, as each puppetdb service uses connections.
          if node['infrastructure']['with_extra_large']
            settings['params']['puppet_enterprise::profile::database::max_connections'] = (default_max_connections * 2)
          end

          settings
        end

        # Return settings.

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

        def memory_reserved_for_os
          (@options[:memory_reserved_for_os] != 0) ? @options[:memory_reserved_for_os] : @defaults[:memory_reserved_for_os]
        end

        # Return a value within a minimum and maximum amount of available processors.

        def calculate_cpu(total, used, percent, minimum, maximum)
          available = total - used
          if available < minimum
            Puppet.debug _("Error: available processors less than minimum: %{available} < minimum: %{minimum}") % { available: available, minimum: minimum }
            return
          end
          percent_value_within_min_max(percent, available, minimum, maximum)
        end

        # Return a value within a minimum and maximum amount of available (minus memory_reserved_for_os) memory.

        def calculate_ram(total, used, percent, minimum, maximum)
          reserved  = memory_reserved_for_os
          available = total - reserved - used
          if available < minimum
            Puppet.debug _("Error: available memory less than minimum: %{available} < minimum: %{minimum}") % { available: available, minimum: minimum }
            return
          end
          percent_value_within_min_max(percent, available, minimum, maximum)
        end

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_processors(processors, small, medium, large)
          return small  if processors <= 4
          return medium if processors <= 8
          return medium if processors <  16
          Puppet.debug _('Using a maximum value for fit_to_processors')
          return large  if processors >= 16
        end

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_memory(memory, small, medium, large)
          # Round up to the nearest power of two (31500 -> 32768) if within a percentage.
          target_memory = nearest_power_of_two(memory)
          if within_percent?(memory, target_memory, @defaults[:fit_to_memory_percentage])
            Puppet.debug _("Rounding %{memory} up to %{target_memory} for fit_to_memory") % { memory: memory, target_memory: target_memory }
            memory = target_memory
          end
          return small  if memory <= 8192
          return medium if memory <= 16384
          return medium if memory <  32768
          Puppet.debug _('Using a maximum value for fit_to_memory')
          return large  if memory >= 32768
        end

        # Return a value or the minimum or maximum, with minimum having a higher precedence than maximum.
        # Different than clamp: [minimum, val, maximum].sort[1]

        def value_within_min_max(val, minimum, maximum)
          value_or_maximum = [val, maximum].min
          [value_or_maximum, minimum].max
        end

        # Return a percentage of a value or the minimum or maximum, with minimum having a higher precedence than maximum.

        def percent_value_within_min_max(percent, val, minimum, maximum)
          percent *= 0.01
          val_percent = (val * percent).to_i
          value_or_maximum = [val_percent, maximum].min
          [value_or_maximum, minimum].max
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
