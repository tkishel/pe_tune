module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Calculate optimized settings.
      class Calculate
        # Calculon Compute!

        def initialize(options)
          @calculate_options = {}
          @calculate_options[:compile_time_factor]      = 2
          @calculate_options[:fit_to_memory_percentage] = 5
          @calculate_options[:memory_per_jruby]         = options[:memory_per_jruby] || 0
          @calculate_options[:memory_reserved_for_os]   = options[:memory_reserved_for_os] || 0
          Puppet.debug("Using #{@calculate_options[:memory_per_jruby]}MB RAM per JRuby") if @calculate_options[:memory_per_jruby] > 0
          Puppet.debug("Using #{@calculate_options[:memory_reserved_for_os]}MB RAM reserved for the operating system") if @calculate_options[:memory_reserved_for_os] > 0
        end

        # Masters and Compile Masters in Monolithic or Split Infrastructures.
        # Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

        def calculate_master_settings(node)
          percent_cpu_threads        = 25
          percent_cpu_jrubies        = 75
          minimum_cpu_threads        = 2
          minimum_cpu_jrubies        = 2
          minimum_mb_puppetserver    = 2048
          mb_per_puppetserver_jruby  = fit_to_memory(node['resources']['ram'], 512, 768, 1024, @calculate_options[:memory_per_jruby])
          mb_puppetserver_code_cache = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          percent_mb_puppetdb        = 10
          minimum_mb_puppetdb        = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_mb_puppetdb        = 8192
          percent_mb_buffers         = 25
          minimum_mb_buffers         = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_mb_buffers         = 16384
          mb_console                 = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          mb_orchestrator            = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          mb_activemq                = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          minimum_mb_os              = fit_to_memory(node['resources']['ram'], 1024, 1024, 1024, @calculate_options[:memory_reserved_for_os])

          if node['infrastructure']['is_monolithic_master']
            percent_cpu_threads        = 75   if node['infrastructure']['with_compile_masters']
            percent_cpu_jrubies        = 25   if node['infrastructure']['with_compile_masters']
            percent_mb_puppetdb        = 20   if node['infrastructure']['with_compile_masters']
            minimum_mb_puppetserver    = 1024 if node['infrastructure']['with_compile_masters']
          else
            percent_cpu_threads        = 0    unless node['classes']['puppetdb']
            percent_cpu_jrubies        = 100  unless node['classes']['puppetdb']
            minimum_mb_puppetserver    = 1024
          end

          maximum_cpu_threads        = (node['resources']['cpu'] * (percent_cpu_threads * 0.01)).to_i
          maximum_cpu_jrubies        = (node['resources']['cpu'] * (percent_cpu_jrubies * 0.01) - 1).to_i

          minimum_mb_buffers         = 0 unless node['classes']['database']
          mb_activemq                = 0 unless node['classes']['amq::broker']
          mb_console                 = 0 unless node['classes']['console']
          mb_orchestrator            = 0 unless node['classes']['orchestrator']
          mb_puppetserver_code_cache = 0 unless node['infrastructure']['with_jruby9k_enabled']

          # The Vegas Renormalization, AKA: the immovable vmpooler vs the unstoppable --force.
          if node['resources']['cpu'] < 4
            minimum_cpu_jrubies = 1
            maximum_cpu_jrubies = 1
            minimum_cpu_threads = 1
            maximum_cpu_threads = 1
          end
          if node['resources']['ram'] < 8096
            minimum_mb_buffers      = 256
            maximum_mb_buffers      = 256
            minimum_mb_puppetserver = 256
          end

          settings = { 'params' => {}, 'totals' => {} }

          if node['classes']['database']
            available_mb_for_buffers = node['resources']['ram'] - minimum_mb_os
            if available_mb_for_buffers < minimum_mb_buffers
              Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
              return {}
            end
            mb_buffers = clamp_percent_of_resource(node['resources']['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          else
            mb_buffers = 0
          end

          if node['classes']['puppetdb']
            command_processing_threads = clamp_percent_of_resource(node['resources']['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
            available_mb_for_puppetdb = node['resources']['ram'] - minimum_mb_os - mb_buffers
            if available_mb_for_puppetdb < minimum_mb_puppetdb
              Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
              return {}
            end
            mb_puppetdb = clamp_percent_of_resource(node['resources']['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
            java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
          else
            command_processing_threads = 0
            mb_puppetdb = 0
          end

          available_mb_for_puppetserver = node['resources']['ram'] - minimum_mb_os - mb_buffers - mb_puppetdb - mb_console - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
          if available_mb_for_puppetserver < minimum_mb_puppetserver
            Puppet.debug("Error: available_mb_for_puppetserver: #{available_mb_for_puppetserver} < minimum_mb_puppetserver: #{minimum_mb_puppetserver}")
            return {}
          end
          jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
          jruby_max_active_instances = clamp_percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)
          mb_jrubies = (jruby_max_active_instances * mb_per_puppetserver_jruby)
          mb_puppetserver = [mb_jrubies, minimum_mb_puppetserver].max
          java_args_for_puppetserver = { 'Xms' => "#{mb_puppetserver}m", 'Xmx' => "#{mb_puppetserver}m" }

          if node['classes']['console']
            java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
          end

          if node['classes']['orchestrator']
            java_args_for_orchestrator = { 'Xms' => "#{mb_orchestrator}m", 'Xmx' => "#{mb_orchestrator}m" }
          end

          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB" if node['classes']['database']
          settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads if node['classes']['puppetdb']
          settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] = jruby_max_active_instances
          settings['params']['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if mb_puppetserver_code_cache > 0
          settings['params']['puppet_enterprise::profile::master::java_args'] = java_args_for_puppetserver
          settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = java_args_for_puppetdb if node['classes']['puppetdb']
          settings['params']['puppet_enterprise::profile::console::java_args'] = java_args_for_console if node['classes']['console']
          settings['params']['puppet_enterprise::profile::orchestrator::java_args'] = java_args_for_orchestrator if node['classes']['orchestrator']
          settings['params']['puppet_enterprise::profile::amq::broker::heap_mb'] = mb_activemq if node['classes']['amq::broker']

          cpu_used = command_processing_threads + jruby_max_active_instances
          ram_used = mb_buffers + mb_puppetdb + mb_puppetserver + mb_puppetserver_code_cache + mb_console + mb_orchestrator + mb_activemq

          settings['totals']['CPU'] = { 'total' => node['resources']['cpu'], 'used' => cpu_used }
          settings['totals']['RAM'] = { 'total' => node['resources']['ram'], 'used' => ram_used }
          settings['totals']['MB_PER_JRUBY'] = mb_per_puppetserver_jruby

          settings
        end

        # Console Hosts in Split Infrastructures.
        # Assumes that pe-console-services is the only service on the host.

        def calculate_console_settings(node)
          percent_mb_console = 75
          minimum_mb_console = fit_to_memory(node['resources']['ram'], 512, 768, 1024)
          maximum_mb_console = 4096
          minimum_mb_os      = fit_to_memory(node['resources']['ram'], 1024, 1024, 1024, @calculate_options[:memory_reserved_for_os])

          settings = { 'params' => {}, 'totals' => {} }

          available_mb_for_console = node['resources']['ram'] - minimum_mb_os
          if available_mb_for_console < minimum_mb_console
            Puppet.debug("Error: available_mb_for_console: #{available_mb_for_console} < minimum_mb_console: #{minimum_mb_console}")
            return {}
          end
          mb_console = clamp_percent_of_resource(node['resources']['ram'], percent_mb_console, minimum_mb_console, maximum_mb_console)
          java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }

          settings['params']['puppet_enterprise::profile::console::java_args'] = java_args_for_console

          cpu_used = 0
          ram_used = mb_console

          settings['totals']['CPU'] = { 'total' => node['resources']['cpu'], 'used' => cpu_used }
          settings['totals']['RAM'] = { 'total' => node['resources']['ram'], 'used' => ram_used }

          settings
        end

        # PuppetDB Hosts in Split Infrastructures.
        # Note: Assumes that pe-puppetdb and (by default) pe-postgresql are the only services on the host.

        def calculate_puppetdb_settings(node)
          percent_cpu_threads = 75
          minimum_cpu_threads = 1
          maximum_cpu_threads = [1, (node['resources']['cpu'] - 1)].max
          percent_mb_puppetdb = (node['classes']['database'] == true) ? 25 : 50
          percent_mb_buffers  = (node['classes']['database'] == true) ? 25 : 0
          minimum_mb_puppetdb = fit_to_memory(node['resources']['ram'], 512, 1024, 2048)
          maximum_mb_puppetdb = 8192
          minimum_mb_buffers  = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_mb_buffers  = 16384
          minimum_mb_os       = fit_to_memory(node['resources']['ram'], 1024, 1024, 1024, @calculate_options[:memory_reserved_for_os])

          minimum_mb_buffers = (node['classes']['database'] == true) ? minimum_mb_buffers : 0

          settings = { 'params' => {}, 'totals' => {} }

          if node['classes']['database']
            available_mb_for_buffers = node['resources']['ram'] - minimum_mb_os
            if available_mb_for_buffers < minimum_mb_buffers
              Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
              return {}
            end
            mb_buffers = clamp_percent_of_resource(node['resources']['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          else
            mb_buffers = 0
          end

          command_processing_threads = clamp_percent_of_resource(node['resources']['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
          available_mb_for_puppetdb = node['resources']['ram'] - minimum_mb_os - mb_buffers
          if available_mb_for_puppetdb < minimum_mb_puppetdb
            Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
            return {}
          end
          mb_puppetdb = clamp_percent_of_resource(node['resources']['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
          java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }

          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB" if node['classes']['database']
          settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
          settings['params']['puppet_enterprise::profile::puppetdb::java_args'] = java_args_for_puppetdb

          cpu_used = command_processing_threads
          ram_used = mb_buffers + mb_puppetdb

          settings['totals']['CPU'] = { 'total' => node['resources']['cpu'], 'used' => cpu_used }
          settings['totals']['RAM'] = { 'total' => node['resources']['ram'], 'used' => ram_used }

          settings
        end

        # External PostgreSQL Hosts in Monolithic and Split Infrastructures.
        # Note: Assumes that pe-postgresql is the only service on the host.

        def calculate_database_settings(node)
          percent_mb_buffers = 25
          minimum_mb_buffers = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
          maximum_mb_buffers = 16384
          minimum_mb_os      = fit_to_memory(node['resources']['ram'], 1024, 1024, 1024, @calculate_options[:memory_reserved_for_os])

          settings = { 'params' => {}, 'totals' => {} }

          available_mb_for_buffers = node['resources']['ram'] - minimum_mb_os
          if available_mb_for_buffers < minimum_mb_buffers
            Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
            return {}
          end
          mb_buffers = clamp_percent_of_resource(node['resources']['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)

          settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"

          cpu_used = 0
          ram_used = mb_buffers

          settings['totals']['CPU'] = { 'total' => node['resources']['cpu'], 'used' => cpu_used }
          settings['totals']['RAM'] = { 'total' => node['resources']['ram'], 'used' => ram_used }

          settings
        end

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
          jruby_lock_time = average_compile_time.to_f * @calculate_options[:compile_time_factor]
          ((run_interval.to_f * available_jrubies.to_f) / jruby_lock_time.to_f).ceil
        end

        # Estimate the theoretical minimum number of jrubies required to manage an infrastructure.

        def calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
          jruby_lock_time = average_compile_time.to_f * @calculate_options[:compile_time_factor]
          ((active_nodes.to_f * jruby_lock_time.to_f) / run_interval.to_f).ceil
        end

        # Internal helper methods.

        private

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_processors(processors, small, medium, large)
          return small  if processors <= 4
          return medium if processors <= 8
          return medium if processors <  16
          Puppet.debug('Using a maximum value for fit_to_processors')
          return large  if processors >= 16
        end

        # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

        def fit_to_memory(memory, small, medium, large, override = 0)
          return override if override && override > 0
          # Round up to the nearest power of two (31500 -> 32768) if within a percentage.
          target_memory = nearest_power_of_two(memory)
          if within_percent?(memory, target_memory, @calculate_options[:fit_to_memory_percentage])
            Puppet.debug("Rounding #{memory} up to #{target_memory} for fit_to_memory")
            memory = target_memory
          end
          return small  if memory <= 8192
          return medium if memory <= 16384
          return medium if memory <  32768
          Puppet.debug('Using a maximum value for fit_to_memory')
          return large  if memory >= 32768
        end

        # Return a percentage of a resource within a minimum and maximum.
        # Note: Alternative: [minimum, resource_percentage, maximum].sort[1]

        def clamp_percent_of_resource(resource, percentage, minimum, maximum)
          percentage *= 0.01
          resource_percentage = (resource * percentage).to_i
          resource_percentage_or_maximum = [resource_percentage, maximum].min
          [resource_percentage_or_maximum, minimum].max
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
