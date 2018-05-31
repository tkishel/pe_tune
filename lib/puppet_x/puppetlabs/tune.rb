#!/opt/puppetlabs/puppet/bin/ruby

require 'facter'
require 'json'
require 'yaml'

# Notes:
#
# This script optimizes the settings documented in tuning_monolithic:
#   https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not optimize the following settings in puppetlabs-puppet_enterprise:
#   autovacuum_max_workers, autovacuum_work_mem, effective_cache_size, maintenance_work_mem, work_mem

# It accepts the following overrides via ENV for testing:
#   export TEST_CPU=8; export TEST_RAM=16384; export TEST_MEM_ROS=512; export TEST_MEM_PJR=768

module PuppetX
  module Puppetlabs
    # Query infrastructure and calculate optimized settings.
    class Tune
      def initialize(options)
        # TODO: Replace/remove this unit test workaround.
        return if options[:unit_test]

        @collected_nodes = {}
        @common_settings = {}

        @option_common_settings = options[:common]
        @option_no_minimum_system_requirements = options[:force]
        @option_output_path = options[:hiera]

        if Puppet[:certname] != Puppet[:server]
          output_not_primary_master_and_exit
        end

        @configuration = PuppetX::Puppetlabs::Configuration.new
        @pe_database_host = @configuration.pe_conf_database_host

        @puppetdb = PuppetX::Puppetlabs::Puppetdb.new
        @replica_masters = @puppetdb.replica_masters
        @primary_masters = @puppetdb.primary_masters
        @compile_masters = @puppetdb.compile_masters
        @console_hosts   = @puppetdb.console_hosts
        @puppetdb_hosts  = @puppetdb.puppetdb_hosts
        @database_hosts  = @puppetdb.database_hosts
      end

      # This method requires an @instance method in another class.

      def get_settings_for_node(certname, settings)
        @configuration::read_hiera_classifier_overrides(certname, settings)
      end

      # This method requires an @instance method in another class.
      # Note: Allow override via ENV for testing.

      def get_resources_for_node(certname)
        resources = {}
        facts = @configuration::read_node_facts(certname)
        resources['cpu'] = facts['processors']['count'].to_i
        resources['ram'] = (facts['memory']['system']['total_bytes'].to_i / 1024 / 1024).to_i
        if ENV['TEST_CPU']
          Puppet.debug("Using TEST_CPU=#{ENV['TEST_CPU']} for #{certname}")
          resources['cpu'] = ENV['TEST_CPU'].to_i
        end
        if ENV['TEST_RAM']
          Puppet.debug("Using TEST_RAM=#{ENV['TEST_RAM']} for #{certname}")
          resources['ram'] = ENV['TEST_RAM'].to_i
        end
        unless meets_minimum_system_requirements?(resources)
          output_node_resources(certname, 'this', resources)
          output_minimum_system_requirements_error_and_exit
        end
        resources
      end

      # Identify this infrastructure.

      def unknown_pe_infrastructure?
        @primary_masters.count.zero? || @pe_database_host.empty?
      end

      def monolithic?
        @console_hosts.count.zero? && @puppetdb_hosts.count.zero?
      end

      def with_compile_masters?
        @compile_masters.count > 0
      end

      def with_external_postgresql?
        if monolithic?
          @primary_masters.count > 0 && @primary_masters.include?(@pe_database_host) == false
        else
          @puppetdb_hosts.count  > 0 && @puppetdb_hosts.include?(@pe_database_host)  == false
        end
      end

      def with_ha?
        @replica_masters.count > 0
      end

      # Output current settings based upon Classifier and Hiera data.

      def output_current_settings
        output_pe_infrastructure_error_and_exit if unknown_pe_infrastructure?

        is_monolithic = monolithic?
        with_compile_masters = with_compile_masters?
        with_external_postgresql = with_external_postgresql?

        output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_external_postgresql)

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @primary_masters.each do |certname|
          settings, duplicates = get_settings_for_node(certname, tunable_settings)
          output_node_settings('Primary Master', certname, settings, duplicates)
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @replica_masters.each do |certname|
          settings, duplicates = get_settings_for_node(certname, tunable_settings)
          output_node_settings('Replica Master', certname, settings, duplicates)
        end

        unless is_monolithic
          # Console Host: Specific to Split Infrastructures. By default, a list of one.
          @console_hosts.each do |certname|
            settings, duplicates = get_settings_for_node(certname, tunable_settings)
            output_node_settings('Console Host', certname, settings, duplicates)
          end

          # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
          @puppetdb_hosts.each do |certname|
            settings, duplicates = get_settings_for_node(certname, tunable_settings)
            output_node_settings('PuppetDB Host', certname, settings, duplicates)
          end
        end

        # External PostgreSQL Host: Applicable to Monolithic and Split Infrastructures.
        if with_external_postgresql
          @database_hosts.each do |certname|
            settings, duplicates = get_settings_for_node(certname, tunable_settings)
            output_node_settings('External PostgreSQL Host', certname, settings, duplicates)
          end
          if @database_hosts.count.zero?
            settings, duplicates = get_settings_for_node(@pe_database_host, tunable_settings)
            output_node_settings('External PostgreSQL Host', @pe_database_host, settings, duplicates)
          end
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        if with_compile_masters
          @compile_masters.each do |certname|
            settings, duplicates = get_settings_for_node(certname, tunable_settings)
            output_node_settings('Compile Master', certname, settings, duplicates)
          end
        end
      end

      # Calculate optimized settings based upon each node's set of services.

      def output_optimized_settings
        output_pe_infrastructure_error_and_exit if unknown_pe_infrastructure?

        is_monolithic = monolithic?
        with_compile_masters = with_compile_masters?
        with_external_postgresql = with_external_postgresql?

        create_output_directories

        output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_external_postgresql)

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @primary_masters.each do |certname|
          resources = get_resources_for_node(certname)
          if is_monolithic
            settings, totals = optimize_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          else
            settings, totals = optimize_master_settings(resources, true, true)
          end
          collect_node_properties(certname, 'Primary Master', resources, settings, totals)
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @replica_masters.each do |certname|
          resources = get_resources_for_node(certname)
          settings, totals = optimize_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          collect_node_properties(certname, 'Replica Master', resources, settings, totals)
        end

        unless is_monolithic
          # Console Host: Specific to Split Infrastructures. By default, a list of one.
          @console_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            settings, totals = optimize_master_settings(resources, false, false)
            collect_node_properties(certname, 'Compile Master', resources, settings, totals)
          end

          # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
          @puppetdb_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            settings, totals = optimize_puppetdb_settings(resources, with_external_postgresql)
            collect_node_properties(certname, 'PuppetDB Host', resources, settings, totals)
          end
        end

        # External PostgreSQL Host: Applicable to Monolithic and Split Infrastructures.
        if with_external_postgresql
          @pe_database_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            settings, totals = optimize_external_postgresql_settings(resources)
            collect_node_properties(certname, 'External PostgreSQL Host', resources, settings, totals)
          end
          if @database_hosts.count.zero?
            resources = get_resources_for_node(@pe_database_host)
            settings, totals = optimize_external_postgresql_settings(resources)
            collect_node_properties(@pe_database_host, 'External PostgreSQL Host', resources, settings, totals)
          end
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        if with_compile_masters
          @compile_masters.each do |certname|
            resources = get_resources_for_node(certname)
            settings, totals = optimize_master_settings(resources, false, false)
            collect_node_properties(certname, 'Compile Master', resources, settings, totals)
          end
        end

        # Output collected information.

        extract_common_settings

        @collected_nodes.each do |certname, properties|
          output_node_resources(certname, properties['profile'], properties['resources'])
          output_node_optimized_settings(certname, properties['settings'])
          output_node_summary(certname, properties['totals'])
        end

        output_common_settings

        create_output_files
      end

      # Collect settings for output.

      def collect_node_properties(certname, profile, resources, settings, totals)
        properties = {
          'profile'   => profile,
          'resources' => resources,
          'settings'  => settings,
          'totals'    => totals,
        }
        @collected_nodes[certname] = properties
      end

      # Extract common settings for common.yaml from <certname>.yaml.

      def extract_common_settings
        return unless @option_common_settings
        nodes_with_setting = {}
        @collected_nodes.each do |certname, properties|
          properties['settings'].each do |setting, value|
            nodes_with_setting[setting] = { certname => value }
          end
        end
        nodes_with_setting.each do |setting, nodes|
          # This is not a deep_merge comparison.
          next unless nodes.values.uniq.length == 1
          @common_settings[setting] = nodes.values[0]
          nodes.each do |certname, _value|
            @collected_nodes[certname]['settings'].delete(setting)
          end
        end
        @common_settings
      end

      # Create the directories for output to Hiera YAML files.

      def create_output_directories
        return unless @option_output_path
        subdirectory = "#{@option_output_path}/nodes"
        return @option_output_path if File.directory?(@option_output_path) && File.directory?(subdirectory)
        Dir.mkdir(@option_output_path)
        output_path_error_and_exit(@option_output_path) unless File.directory?(@option_output_path)
        Dir.mkdir(subdirectory)
        output_path_error_and_exit(subdirectory) unless File.directory?(subdirectory)
        @option_output_path
      end

      # Output Hiera YAML files.

      def create_output_files
        return unless @option_output_path
        return if @collected_nodes.empty?
        @collected_nodes.each do |certname, properties|
          next if properties['settings'].empty?
          output_file = "#{@option_output_path}/nodes/#{certname}.yaml"
          File.write(output_file, properties['settings'].to_yaml)
          output("## Wrote Hiera YAML file: #{output_file}\n\n")
        end
        return if @common_settings.empty?
        output_file = "#{@option_output_path}/common.yaml"
        File.write(output_file, @common_settings.to_yaml)
      end

      # Verify minimum system requirements.

      def meets_minimum_system_requirements?(resources)
        return true if @option_no_minimum_system_requirements
        (resources['cpu'] >= 4 && resources['ram'] >= 8192)
      end

      # Consolidate output.

      def output(info)
        puts info
      end

      # Output highlighted output.

      def output_data(info)
        puts "\e[0;32m#{info}\e[0m"
      end

      # Output infrastucture information.

      def output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_external_postgresql)
        type = is_monolithic ? 'Monolithic' : 'Split'
        w_cm = with_compile_masters ? ' with Compile Masters' : ''
        w_ep = with_external_postgresql ? ' with External PostgreSQL' : ''
        output("### Puppet Infrastructure Summary: Found a #{type} Infrastructure#{w_cm}#{w_ep}\n\n")
      end

      # Output current information.

      def output_node_settings(profile, certname, settings, duplicates)
        output("## Current settings for #{profile} #{certname}\n\n")
        output_data(JSON.pretty_generate(settings))
        output("\n")
        output_node_duplicate_settings(duplicates)
      end

      def output_node_duplicate_settings(duplicates)
        return if duplicates.count.zero?
        output("## Duplicate settings found in the Classifier and in Hiera:\n\n")
        output_data(duplicates.join("\n"))
        output("\n")
        output("## Define settings in Hiera (preferred) or the Classifier, but not both.\n\n")
      end

      # Output optimized information.

      def output_node_optimized_settings(certname, settings)
        return if settings.empty?
        output("## Specify the following optimized settings in Hiera in nodes/#{certname}.yaml\n\n")
        output_data(settings.to_yaml)
      end

      def output_node_resources(certname, profile, resources)
        output("## Found: #{resources['cpu']} CPU(s) / #{resources['ram']} MB RAM for #{profile} #{certname}")
      end

      def output_node_summary(certname, totals)
        return if totals.empty?
        if totals['CPU']
          total = totals['CPU']['total']
          used = totals['CPU']['used']
          free = total - used
          output("## CPU Summary: Total/Used/Free: #{total}/#{used}/#{free} for #{certname}")
        end
        if totals['RAM']
          total = totals['RAM']['total']
          used = totals['RAM']['used']
          free = total - used
          output("## RAM Summary: Total/Used/Free: #{total}/#{used}/#{free} for #{certname}")
        end
        if totals['MB_PER_JRUBY']
          mb_per_puppetserver_jruby = totals['MB_PER_JRUBY']
          output("## JVM Summary: Using #{mb_per_puppetserver_jruby} MB per Puppet Server JRuby for #{certname}\n\n")
        end
      end

      def output_common_settings
        return unless @option_common_settings
        return if @common_settings.empty?
        output("## Specify the following optimized settings in Hiera in common.yaml\n\n")
        output(@common_settings.to_yaml)
        output("\n")
      end

      # Output errors and exit.

      def output_not_primary_master_and_exit
        Puppet.err('This command must be run on the Primary Master')
        exit 1
      end

      def output_path_error_and_exit(directory)
        Puppet.err("Error: Unable to create output directory: #{directory}")
        exit 1
      end

      def output_pe_infrastructure_error_and_exit
        Puppet.err('Puppet Infrastructure Summary: Unknown Infrastructure')
        Puppet.err('Error: Unable to find a Primary Master via a PuppetDB query.')
        Puppet.err('Verify PE Infrastructure node groups in the Console.')
        Puppet.err('Rerun this command with --debug for more information.')
        exit 1
      end

      def output_minimum_system_requirements_error_and_exit(certname = 'This')
        Puppet.err("#{certname} does not meet the minimum system requirements to optimize its settings")
        exit 1
      end

      # Calculon Compute!

      # List of settings optimized by this module.

      def tunable_settings
        [
          'puppet_enterprise::master::puppetserver::jruby_max_active_instances',
          'puppet_enterprise::master::puppetserver::reserved_code_cache',
          'puppet_enterprise::profile::amq::broker::heap_mb',
          'puppet_enterprise::profile::console::java_args',
          'puppet_enterprise::profile::database::shared_buffers',
          'puppet_enterprise::profile::master::java_args',
          'puppet_enterprise::profile::orchestrator::java_args',
          'puppet_enterprise::profile::puppetdb::java_args',
          'puppet_enterprise::puppetdb::command_processing_threads',
        ]
      end

      # Primary Masters in Monolithic Infrastructures.
      # Note: Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.

      def optimize_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
        output_minimum_system_requirements_error_and_exit unless meets_minimum_system_requirements?(resources)

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
        mb_puppetserver_code_cache = 0 unless jruby_9k_enabled?

        settings = {}
        totals = {}

        if with_external_postgresql
          mb_buffers = 0
        else
          available_mb_for_buffers = resources['ram'] - minimum_mb_os
          if available_mb_for_buffers < minimum_mb_buffers
            Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
            output_minimum_system_requirements_error_and_exit
          end
          mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
        end

        command_processing_threads = clamp_percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)

        available_mb_for_puppetdb = resources['ram'] - minimum_mb_os - mb_buffers
        if available_mb_for_puppetdb < minimum_mb_puppetdb
          Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
          output_minimum_system_requirements_error_and_exit
        end

        mb_puppetdb = clamp_percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
        java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
        # java_args_for_puppetdb['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_puppetdb >= minimum_mb_g1gc)

        available_mb_for_puppetserver = resources['ram'] - minimum_mb_os - mb_buffers - mb_puppetdb - mb_console - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
        if available_mb_for_puppetserver < minimum_mb_puppetserver
          Puppet.debug("Error: available_mb_for_puppetserver: #{available_mb_for_puppetserver} < minimum_mb_puppetserver: #{minimum_mb_puppetserver}")
          output_minimum_system_requirements_error_and_exit
        end

        jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
        jruby_max_active_instances = clamp_percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)

        mb_jrubies = (jruby_max_active_instances * mb_per_puppetserver_jruby)
        mb_puppetserver = [mb_jrubies, minimum_mb_puppetserver].max
        java_args_for_puppetserver = { 'Xms' => "#{mb_puppetserver}m", 'Xmx' => "#{mb_puppetserver}m" }
        # java_args_for_puppetserver['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_puppetserver >= minimum_mb_g1gc)

        java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
        # java_args_for_console['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_console >= minimum_mb_g1gc)

        java_args_for_orchestrator = { 'Xms' => "#{mb_orchestrator}m", 'Xmx' => "#{mb_orchestrator}m" }
        # java_args_for_orchestrator['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_orchestrator >= minimum_mb_g1gc)

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

      def optimize_master_settings(resources, with_activemq, with_orchestrator)
        output_minimum_system_requirements_error_and_exit unless meets_minimum_system_requirements?(resources)

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
        mb_puppetserver_code_cache = 0 unless jruby_9k_enabled?

        settings = {}
        totals = {}

        available_mb_for_puppetserver = resources['ram'] - minimum_mb_os - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
        if available_mb_for_puppetserver < minimum_mb_puppetserver
          Puppet.debug("Error: available_mb_for_puppetserver: #{available_mb_for_puppetserver} < minimum_mb_puppetserver: #{minimum_mb_puppetserver}")
          output_minimum_system_requirements_error_and_exit
        end

        jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
        jruby_max_active_instances = clamp_percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)
        settings['puppet_enterprise::master::jruby_max_active_instances'] = jruby_max_active_instances

        settings['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if mb_puppetserver_code_cache > 0

        mb_jrubies = (jruby_max_active_instances * mb_per_puppetserver_jruby)
        mb_puppetserver = [mb_jrubies, minimum_mb_puppetserver].max
        java_args_for_puppetserver = { 'Xms' => "#{mb_puppetserver}m", 'Xmx' => "#{mb_puppetserver}m" }
        # java_args_for_puppetserver['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_puppetserver >= minimum_mb_g1gc)
        settings['puppet_enterprise::profile::master::java_args'] = java_args_for_puppetserver

        if with_orchestrator
          java_args_for_orchestrator = { 'Xms' => "#{mb_orchestrator}m", 'Xmx' => "#{mb_orchestrator}m" }
          # java_args_for_orchestrator['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_orchestrator >= minimum_mb_g1gc)
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

      def optimize_console_settings(resources)
        output_minimum_system_requirements_error_and_exit unless meets_minimum_system_requirements?(resources)

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
          output_minimum_system_requirements_error_and_exit
        end

        mb_console = clamp_percent_of_resource(resources['ram'], percent_mb_console, minimum_mb_console, maximum_mb_console)
        java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
        # java_args_for_console['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_console >= minimum_mb_g1gc)
        settings['puppet_enterprise::profile::console::java_args'] = java_args_for_console

        ram_used = mb_console
        totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

        [settings, totals]
      end

      # PuppetDB Hosts in Split Infrastructures.
      # Note: Assumes that pe-puppetdb and (by default) pe-postgresql are the only services on the host.

      def optimize_puppetdb_settings(resources, with_external_postgresql)
        output_minimum_system_requirements_error_and_exit unless meets_minimum_system_requirements?(resources)

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
            output_minimum_system_requirements_error_and_exit
          end
          mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
        end

        command_processing_threads = clamp_percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
        settings['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads

        available_mb_for_puppetdb = resources['ram'] - minimum_mb_os - mb_buffers

        if available_mb_for_puppetdb < minimum_mb_puppetdb
          Puppet.debug("Error: available_mb_for_puppetdb: #{available_mb_for_puppetdb} < minimum_mb_puppetdb: #{minimum_mb_puppetdb}")
          output_minimum_system_requirements_error_and_exit
        end

        mb_puppetdb = clamp_percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
        java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
        # java_args_for_puppetdb['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_puppetdb >= minimum_mb_g1gc)
        settings['puppet_enterprise::profile::puppetdb::java_args'] = java_args_for_puppetdb

        cpu_used = command_processing_threads
        ram_used = mb_buffers + mb_puppetdb
        totals['CPU'] = { 'total' => resources['cpu'], 'used' => cpu_used }
        totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

        [settings, totals]
      end

      # External PostgreSQL Hosts in Monolithic and Split Infrastructures.
      # Note: Assumes that pe-postgresql is the only service on the host.

      def optimize_external_postgresql_settings(resources)
        output_minimum_system_requirements_error_and_exit unless meets_minimum_system_requirements?(resources)

        percent_mb_buffers = 25
        minimum_mb_buffers = fit_to_memory(resources['ram'], 2048, 3072, 4096)
        maximum_mb_buffers = 16384
        minimum_mb_os      = reserved_memory_os

        settings = {}
        totals = {}

        available_mb_for_buffers = resources['ram'] - minimum_mb_os
        if available_mb_for_buffers < minimum_mb_buffers
          Puppet.debug("Error: available_mb_for_buffers: #{available_mb_for_buffers} < minimum_mb_buffers: #{minimum_mb_buffers}")
          output_minimum_system_requirements_error_and_exit
        end

        mb_buffers = clamp_percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
        settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"

        ram_used = mb_buffers
        totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

        [settings, totals]
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

      # Return a number as a computer-science number.

      def nearest_power_of_two(number)
        return 0 if number <= 0
        exponent = Math.log2 number
        higher_power = 2**exponent.ceil
        lower_power  = 2**exponent.floor
        ((higher_power - number) <= (number - lower_power)) ? higher_power : lower_power
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

      # JRuby 9K is the default in 2018.x.

      def jruby_9k_enabled?
        pe_server_version = Facter.value('pe_server_version') || 'NOT NIL'
        pe_server_version.start_with? '2018'
      end
    end
  end
end

# The remainder of this file allows this class to be executed as a standalone script.
# TODO: Delete the remainder of this file prior to release of this script as a module.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'hocon'
  require 'optparse'
  require 'puppet'
  require 'puppet/util/puppetdb'

  # The location of enterprise modules varies from version to version.
  enterprise_modules = ['pe_infrastructure', 'pe_install', 'pe_manager']
  ent_mod = '/opt/puppetlabs/server/data/enterprise/modules'
  env_mod = '/opt/puppetlabs/server/data/environments/enterprise/modules'
  enterprise_module_path = File.directory?(ent_mod) ? ent_mod : env_mod
  enterprise_modules.each do |enterprise_module|
    enterprise_module_lib = "#{enterprise_module_path}/#{enterprise_module}/lib"
    $LOAD_PATH.unshift(enterprise_module_lib) unless $LOAD_PATH.include?(enterprise_module_lib)
  end

  require 'puppet/util/pe_conf'
  require 'puppet/util/pe_conf/recover'

  module PuppetX
    module Puppetlabs
      # This class duplicates lib/puppet_x/configuration.rb
      # Read pe.conf, and query facts and overrides via Recover.
      class Configuration
        attr_reader :environment
        attr_reader :pe_conf
        attr_reader :pe_conf_database_host

        def initialize
          # PE-15116 results in Puppet[:environment] being set to 'enterprise' in the infrastructure face.
          @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
          @pe_conf = read_pe_conf
          pe_conf_puppet_master_host = @pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
          pe_conf_puppet_master_host = Puppet[:certname] if pe_conf_puppet_master_host == '%{::trusted.certname}'
          Puppet.debug("Found pe.conf puppet_master_host: #{pe_conf_puppet_master_host}")
          pe_conf_puppetdb_host = @pe_conf['puppet_enterprise::puppetdb_host'] || pe_conf_puppet_master_host
          Puppet.debug("Found pe.conf pe_puppetdb_host: #{pe_conf_puppetdb_host}")
          @pe_conf_database_host = @pe_conf['puppet_enterprise::database_host'] || pe_conf_puppetdb_host
          Puppet.debug("Found pe.conf pe_database_host: #{@pe_conf_database_host}")
        end

        def read_pe_conf
          pe_conf_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
          Puppet.debug("Reading: #{pe_conf_file}")
          if File.exist?(pe_conf_file)
            Puppet.debug("Found: #{pe_conf_file}")
            pe_conf = Hocon.load(pe_conf_file)
          else
            Puppet.err("File does not exist: #{pe_conf_file}")
            pe_conf = {}
          end
          pe_conf
        end

        # PE-24106 changes Recover to a class with instance methods.

        def recover_without_instance?
          defined?(Puppet::Util::Pe_conf::Recover.facts_for_node) == 'method'
        end

        # In some versions, Puppet::Util::Pe_conf::Recover does not implement get_node_terminus() and implements find_hiera_overrides(params, facts, environment)

        def recover_with_node_terminus?
          defined?(Puppet::Util::Pe_conf::Recover.get_node_terminus) == 'method'
        end

        def read_node_facts(certname)
          node_facts = {}
          if recover_without_instance?
            facts_hash = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
            if facts_hash.key?('puppetversion')
              node_facts = facts_hash
            else
              # Prior to PE-22444, facts are returned as a Hash with elements in this format: {"name"=>"puppetversion", "value"=>"4.10.10"} => nil
              facts_hash.each do |fact, _nil|
                node_facts[fact['name']] = fact['value']
              end
            end
          else
            recover = Puppet::Util::Pe_conf::Recover.new
            node_facts = recover.facts_for_node(certname, @environment)
          end
          node_facts
        end

        def read_hiera_classifier_overrides(certname, settings)
          if recover_without_instance?
            node_facts = Puppet::Util::Pe_conf::Recover.facts_for_node(certname, @environment)
            if recover_with_node_terminus?
              node_terminus = Puppet::Util::Pe_conf::Recover.get_node_terminus
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
            else
              overrides_hiera = Puppet::Util::Pe_conf::Recover.find_hiera_overrides(settings, node_facts, @environment)
            end
            overrides_classifier = Puppet::Util::Pe_conf::Recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
          else
            recover = Puppet::Util::Pe_conf::Recover.new
            node_facts = recover.facts_for_node(certname, @environment)
            node_terminus = recover.get_node_terminus
            overrides_hiera = recover.find_hiera_overrides(certname, settings, node_facts, @environment, node_terminus)
            overrides_classifier = recover.classifier_overrides_for_node(certname, node_facts, node_facts['::trusted'])
          end
          overrides = overrides_hiera
          duplicates = []
          # Classifier settings take precedence over Hiera settings.
          overrides_classifier.each do |k, v|
            # find_hiera_overrides() returns the specified settings, while classifier_overrides_for_node() returns all settings.
            next unless settings.include?(k)
            # This setting is specifed in both the Classifier and Hiera.
            if overrides.key?(k)
              Puppet.debug("# Duplicate settings for #{certname}: #{k} Classifier: #{v} Hiera: #{overrides_hiera[k]}")
              duplicates.push(k)
            end
            overrides[k] = v
          end
          [overrides, duplicates]
        end
      end

      # This class duplicates lib/puppet_x/puppetdb.rb
      # Query PuppetDB via its API.
      class Puppetdb
        attr_reader :replica_masters
        attr_reader :primary_masters
        attr_reader :compile_masters
        attr_reader :console_hosts
        attr_reader :puppetdb_hosts
        attr_reader :database_hosts

        def initialize
          # PE-15116 results in Puppet[:environment] being set to 'enterprise' in the infrastructure face.
          environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
          @replica_masters = get_pe_infra_nodes_by_class('Primary_master_replica', environment)
          @primary_masters = get_pe_infra_nodes_by_class('Certificate_authority', environment) - @replica_masters
          @compile_masters = get_pe_infra_nodes_by_class('Master', environment)   - @primary_masters - @replica_masters
          @console_hosts   = get_pe_infra_nodes_by_class('Console', environment)  - @primary_masters - @replica_masters
          @puppetdb_hosts  = get_pe_infra_nodes_by_class('Puppetdb', environment) - @primary_masters - @replica_masters
          @database_hosts  = get_pe_infra_nodes_by_class('Database', environment) - @primary_masters - @replica_masters
        end

        # Note: This is an alternative to get_pe_infra_nodes() in puppetlabs-pe_manager.

        def get_pe_infra_nodes_by_class(class_name, environment = 'production')
          Puppet.debug("Querying PuppetDB for Class: Puppet_enterprise::Profile::#{class_name}")
          pql = ['from', 'resources',
                  ['extract', ['certname', 'parameters'],
                    ['and',
                      ['=', 'type', 'Class'],
                      ['=', 'environment', environment],
                      ['=', ['node', 'active'], true],
                      ['=', 'title', "Puppet_enterprise::Profile::#{class_name}"]
                    ]
                  ]
                ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          Puppet.debug(results)
          results.map { |resource| resource.fetch('certname') }
        end
      end
    end
  end

  # This code replaces: lib/puppet/face/infrastructure/tune.rb

  Puppet.initialize_settings
  Puppet::Util::Log.newdestination :console

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: tune.rb [options]'
    opts.separator ''
    opts.separator 'Summary: Inspect infrastructure and output optimized settings for services'
    opts.separator ''
    opts.separator 'Options:'
    opts.separator ''
    options[:common] = false
    opts.on('--common', 'Extract common settings from node-specific settings') do
      options[:common] = true
    end
    options[:current] = false
    opts.on('--current', 'Output current settings and exit') do
      options[:current] = true
    end
    options[:debug] = false
    opts.on('--debug', 'Enable logging of debug information') do
      options[:debug] = true
    end
    options[:force] = false
    opts.on('--force', 'Do not enforce minimum system requirements') do
      options[:force] = true
    end
    opts.on('--hiera DIRECTORY', 'Output Hiera YAML files to the specified directory') do |hi|
      options[:hiera] = hi
    end
    opts.on('-h', '--help', 'Display help') do
      puts opts
      puts
      exit 0
    end
  end
  parser.parse!

  Puppet.debug = options[:debug]

  Puppet.debug("Command Options: #{options}")

  Tune = PuppetX::Puppetlabs::Tune.new(options)

  if options[:current]
    Tune.output_current_settings
  else
    Tune.output_optimized_settings
  end
end
