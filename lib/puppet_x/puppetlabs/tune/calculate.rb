module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Calculate optimized settings.
      class Calculate
        # Primary Masters in Monolithic Infrastructures.
        # Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

        def initialize
          # Calculon Compute!
        end

        def calculate_monolithic_master_settings(resources, with_jruby_9k, with_compile_masters, with_external_postgresql)
          percent_cpu_threads        = with_compile_masters ? 75 : 25
          percent_cpu_jrubies        = with_compile_masters ? 25 : 75
          minimum_cpu_threads        = 2
          minimum_cpu_jrubies        = 2
          maximum_cpu_threads        = (resources['cpu'] * (percent_cpu_threads * 0.01)).to_i     # fit_to_processors(resources['cpu'], 2, 6, 10)
          maximum_cpu_jrubies        = (resources['cpu'] * (percent_cpu_jrubies * 0.01) - 1).to_i # fit_to_processors(resources['cpu'], 2, 6, 10)
          minimum_mb_puppetserver    = with_compile_masters ? 1024 : 2048
          mb_per_puppetserver_jruby  = memory_per_jruby(resources['ram'])
          mb_puppetserver_code_cache = (resources['ram'] < 2048) ? 48 : 512
          percent_mb_puppetdb        = with_compile_masters ? 20 : 10
          minimum_mb_puppetdb        = fit_to_memory(resources['ram'], 512, 1024, 2048)
          maximum_mb_puppetdb        = 8192
          percent_mb_buffers         = 25
          minimum_mb_buffers         = fit_to_memory(resources['ram'], 2048, 3072, 4096)
          maximum_mb_buffers         = 16384
          mb_console                 = fit_to_memory(resources['ram'], 512, 768, 1024)
          mb_orchestrator            = fit_to_memory(resources['ram'], 512, 768, 1024)
          mb_activemq                = fit_to_memory(resources['ram'], 512, 1024, 2048)
          minimum_mb_os              = reserved_memory_os
          # minimum_mb_g1gc          = 2048

          minimum_mb_buffers         = 0 if with_external_postgresql
          mb_puppetserver_code_cache = 0 unless with_jruby_9k

          settings = {}
          totals = {}

          if with_external_postgresql
            mb_buffers = 0
          else
            available_mb_for_buffers = resources['ram'] - minimum_mb_os
            if available_mb_for_buffers < minimum_mb_buffers
              Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
              return empty_settings_and_totals
            end
            mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
            settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
          end

          command_processing_threads = clamp_percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)

          available_mb_for_puppetdb = resources['ram'] - minimum_mb_os - mb_buffers
          if available_mb_for_puppetdb < minimum_mb_puppetdb
            Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
            return empty_settings_and_totals
          end

          mb_puppetdb = clamp_percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
          java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
          # java_args_for_puppetdb['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_puppetdb >= minimum_mb_g1gc)

          available_mb_for_puppetserver = resources['ram'] - minimum_mb_os - mb_buffers - mb_puppetdb - mb_console - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
          if available_mb_for_puppetserver < minimum_mb_puppetserver
            Puppet.debug("Error: available_mb_for_puppetserver: #{available_mb_for_puppetserver} < minimum_mb_puppetserver: #{minimum_mb_puppetserver}")
            return empty_settings_and_totals
          end

          jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
          jruby_max_active_instances = clamp_percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)

          mb_jrubies = (jruby_max_active_instances * mb_per_puppetserver_jruby)
          mb_puppetserver = [mb_jrubies, minimum_mb_puppetserver].max
          java_args_for_puppetserver = { 'Xms' => "#{mb_puppetserver}m", 'Xmx' => "#{mb_puppetserver}m" }
          # java_args_for_puppetserver['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_puppetserver >= minimum_mb_g1gc)

          java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
          # java_args_for_console['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_console >= minimum_mb_g1gc)

          java_args_for_orchestrator = { 'Xms' => "#{mb_orchestrator}m", 'Xmx' => "#{mb_orchestrator}m" }
          # java_args_for_orchestrator['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_orchestrator >= minimum_mb_g1gc)

          settings['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads
          settings['puppet_enterprise::master::jruby_max_active_instances'] = jruby_max_active_instances
          settings['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if mb_puppetserver_code_cache > 0
          settings['puppet_enterprise::profile::master::java_args'] = java_args_for_puppetserver
          settings['puppet_enterprise::profile::puppetdb::java_args'] = java_args_for_puppetdb
          settings['puppet_enterprise::profile::console::java_args'] = java_args_for_console
          settings['puppet_enterprise::profile::orchestrator::java_args'] = java_args_for_orchestrator
          settings['puppet_enterprise::profile::amq::broker::heap_mb'] = mb_activemq

          cpu_used = command_processing_threads + jruby_max_active_instances
          ram_used = mb_buffers + mb_puppetdb + mb_puppetserver + mb_console + mb_orchestrator + mb_activemq + mb_puppetserver_code_cache
          totals['CPU'] = { 'total' => resources['cpu'], 'used' => cpu_used }
          totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }
          totals['MB_PER_JRUBY'] = mb_per_puppetserver_jruby

          [settings, totals]
        end

        # Compile Masters in both Monolithic and Split Infrastructures, and Primary Masters in Split Infrastructures.
        # Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

        def calculate_master_settings(resources, with_jruby_9k, with_activemq, with_orchestrator)
          minimum_cpu_jrubies        = 1
          maximum_cpu_jrubies        = resources['cpu'] - 1
          minimum_mb_puppetserver    = 1024
          mb_per_puppetserver_jruby  = memory_per_jruby(resources['ram'])
          mb_puppetserver_code_cache = (resources['ram'] < 2048) ? 48 : 512
          mb_orchestrator            = fit_to_memory(resources['ram'], 512, 768, 1024)
          mb_activemq                = fit_to_memory(resources['ram'], 512, 1024, 2048)
          minimum_mb_os              = reserved_memory_os
          # minimum_mb_g1gc          = 2048

          mb_orchestrator            = with_orchestrator ? mb_orchestrator : 0
          mb_activemq                = with_activemq     ? mb_activemq     : 0
          mb_puppetserver_code_cache = 0 unless with_jruby_9k

          settings = {}
          totals = {}

          available_mb_for_puppetserver = resources['ram'] - minimum_mb_os - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
          if available_mb_for_puppetserver < minimum_mb_puppetserver
            Puppet.debug("Error: available_mb_for_puppetserver: #{available_mb_for_puppetserver} < minimum_mb_puppetserver: #{minimum_mb_puppetserver}")
            return empty_settings_and_totals
          end

          jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
          jruby_max_active_instances = clamp_percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)
          settings['puppet_enterprise::master::jruby_max_active_instances'] = jruby_max_active_instances

          settings['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if mb_puppetserver_code_cache > 0

          mb_jrubies = (jruby_max_active_instances * mb_per_puppetserver_jruby)
          mb_puppetserver = [mb_jrubies, minimum_mb_puppetserver].max
          java_args_for_puppetserver = { 'Xms' => "#{mb_puppetserver}m", 'Xmx' => "#{mb_puppetserver}m" }
          # java_args_for_puppetserver['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_puppetserver >= minimum_mb_g1gc)
          settings['puppet_enterprise::profile::master::java_args'] = java_args_for_puppetserver

          if with_orchestrator
            java_args_for_orchestrator = { 'Xms' => "#{mb_orchestrator}m", 'Xmx' => "#{mb_orchestrator}m" }
            # java_args_for_orchestrator['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_orchestrator >= minimum_mb_g1gc)
            settings['puppet_enterprise::profile::orchestrator::java_args'] = java_args_for_orchestrator
          end

          if with_activemq
            settings['puppet_enterprise::profile::amq::broker::heap_mb'] = mb_activemq
          end

          cpu_used = jruby_max_active_instances
          ram_used = mb_puppetserver + mb_activemq + mb_orchestrator + mb_puppetserver_code_cache
          totals['CPU'] = { 'total' => resources['cpu'], 'used' => cpu_used }
          totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }
          totals['MB_PER_JRUBY'] = mb_per_puppetserver_jruby

          [settings, totals]
        end

        # Console Hosts in Split Infrastructures.
        # Assumes that pe-console-services is the only service on the host.

        def calculate_console_settings(resources)
          percent_mb_console = 75
          minimum_mb_console = fit_to_memory(resources['ram'], 512, 768, 1024)
          maximum_mb_console = 4096
          minimum_mb_os      = reserved_memory_os
          # minimum_mb_g1gc  = 2048

          settings = {}
          totals = {}

          available_mb_for_console = resources['ram'] - minimum_mb_os
          if available_mb_for_console < minimum_mb_console
            Puppet.debug("Error: available_mb_for_console: #{available_mb_for_console} < minimum_mb_console: #{minimum_mb_console}")
            return empty_settings_and_totals
          end

          mb_console = clamp_percent_of_resource(resources['ram'], percent_mb_console, minimum_mb_console, maximum_mb_console)
          java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
          # java_args_for_console['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_console >= minimum_mb_g1gc)
          settings['puppet_enterprise::profile::console::java_args'] = java_args_for_console

          ram_used = mb_console
          totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

          [settings, totals]
        end

        # PuppetDB Hosts in Split Infrastructures.
        # Note: Assumes that pe-puppetdb and (by default) pe-postgresql are the only services on the host.

        def calculate_puppetdb_settings(resources, with_external_postgresql)
          percent_cpu_threads = 75
          minimum_cpu_threads = 1
          maximum_cpu_threads = resources['cpu'] - 1
          percent_mb_puppetdb = with_external_postgresql ? 50 : 25
          percent_mb_buffers  = with_external_postgresql ? 0  : 25
          minimum_mb_puppetdb = fit_to_memory(resources['ram'], 512, 1024, 2048)
          maximum_mb_puppetdb = 8192
          minimum_mb_buffers  = fit_to_memory(resources['ram'], 2048, 3072, 4096)
          maximum_mb_buffers  = 16384
          minimum_mb_os       = reserved_memory_os
          # minimum_mb_g1gc   = 2048

          minimum_mb_buffers = with_external_postgresql ? 0 : minimum_mb_buffers

          settings = {}
          totals = {}

          if with_external_postgresql
            mb_buffers = 0
          else
            available_mb_for_buffers = resources['ram'] - minimum_mb_os
            if available_mb_for_buffers < minimum_mb_buffers
              Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
              return empty_settings_and_totals
            end
            mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
            settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
          end

          command_processing_threads = clamp_percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
          settings['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads

          available_mb_for_puppetdb = resources['ram'] - minimum_mb_os - mb_buffers

          if available_mb_for_puppetdb < minimum_mb_puppetdb
            Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
            return empty_settings_and_totals
          end

          mb_puppetdb = clamp_percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
          java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
          # java_args_for_puppetdb['XX:+UseG1GC'] = '' if (with_jruby_9k == false) && (mb_puppetdb >= minimum_mb_g1gc)
          settings['puppet_enterprise::profile::puppetdb::java_args'] = java_args_for_puppetdb

          cpu_used = command_processing_threads
          ram_used = mb_buffers + mb_puppetdb
          totals['CPU'] = { 'total' => resources['cpu'], 'used' => cpu_used }
          totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

          [settings, totals]
        end

        # External PostgreSQL Hosts in Monolithic and Split Infrastructures.
        # Note: Assumes that pe-postgresql is the only service on the host.

        def calculate_external_postgresql_settings(resources)
          percent_mb_buffers = 25
          minimum_mb_buffers = fit_to_memory(resources['ram'], 2048, 3072, 4096)
          maximum_mb_buffers = 16384
          minimum_mb_os      = reserved_memory_os

          settings = {}
          totals = {}

          available_mb_for_buffers = resources['ram'] - minimum_mb_os
          if available_mb_for_buffers < minimum_mb_buffers
            Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
            return empty_settings_and_totals
          end

          mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"

          ram_used = mb_buffers
          totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

          [settings, totals]
        end

        # Internal helper methods.

        private

        # Return this in response to an allocation error.

        def empty_settings_and_totals
          [{}, {}]
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

        # Note: Allow override via ENV for testing.

        def reserved_memory_os
          if ENV['TEST_MEM_ROS']
            Puppet.debug("Using TEST_MEM_ROS=#{ENV['TEST_MEM_ROS']} for reserved_memory_os")
            return ENV['TEST_MEM_ROS'].to_i
          end
          1024
        end

        # Note: Allow override via ENV for testing.

        def memory_per_jruby(memory)
          if ENV['TEST_MEM_PJR']
            Puppet.debug("Using TEST_MEM_PJR=#{ENV['TEST_MEM_PJR']} for memory_per_jruby")
            return ENV['TEST_MEM_PJR'].to_i
          end
          fit_to_memory(memory, 512, 768, 1024)
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
