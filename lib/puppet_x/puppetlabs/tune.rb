#!/opt/puppetlabs/puppet/bin/ruby

# Notes:
#
# This script optimizes the settings documented in tuning_monolithic:
#   https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not optimize the following settings in puppetlabs-puppet_enterprise:
#   autovacuum_max_workers, autovacuum_work_mem, effective_cache_size, maintenance_work_mem, work_mem

# It accepts the following overrides (for the primary master) via ENV for testing:
#   export TUNE_CPU=8; export TUNE_RAM=16384;

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current or calculate optimized settings.
    class Tune
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

      def initialize(options)
        # TODO: Replace/remove this unit test workaround.
        return if options[:unit_test]

        @collected_nodes = {}
        @common_settings = {}

        @option_common_settings = options[:common]
        @option_no_minimum_system_requirements = options[:force]
        @option_output_path = options[:hiera]

        calculate_options = {}
        calculate_options[:memory_per_jruby] = options[:memory_per_jruby]
        calculate_options[:memory_reserved_for_os] = options[:memory_reserved_for_os]

        # PE-15116 overrides environment and environmentpath in the infrastructure face.
        @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
        @environmentpath = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environmentpath --section master').chomp

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new(calculate_options)
        @configurator = PuppetX::Puppetlabs::Tune::Configuration.new

        if Puppet[:certname] != @configurator::find_pe_conf_puppet_master_host
          output_not_primary_master_and_exit
        end

        @pe_database_host = @configurator::find_pe_conf_database_host || Puppet[:certname]

        # https://github.com/puppetlabs/puppetlabs-pe_infrastructure/blob/irving/lib/puppet_x/puppetlabs/meep/defaults.rb

        @hosts_with_primary_master_replica = get_nodes_with_class('Primary_master_replica')
        @hosts_with_certificate_authority  = get_nodes_with_class('Certificate_authority')
        @hosts_with_master                 = get_nodes_with_class('Master')
        @hosts_with_compile_master         = get_nodes_with_class('Compile_master')
        @hosts_with_console                = get_nodes_with_class('Console')
        @hosts_with_puppetdb               = get_nodes_with_class('Puppetdb')
        @hosts_with_database               = get_nodes_with_class('Database')
        @hosts_with_amq_broker             = get_nodes_with_class('Amq::Broker')
        @hosts_with_orchestrator           = get_nodes_with_class('Orchestrator')

        @replica_masters = @hosts_with_primary_master_replica
        @primary_masters = @hosts_with_certificate_authority - @replica_masters
        @compile_masters = @hosts_with_master   - @primary_masters - @replica_masters
        @console_hosts   = @hosts_with_console  - @primary_masters - @replica_masters
        @puppetdb_hosts  = @hosts_with_puppetdb - @primary_masters - @replica_masters - @compile_masters
        @external_database_hosts = @hosts_with_database - @primary_masters - @replica_masters - @compile_masters
      end

      # Interfaces to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover

      def get_nodes_with_class(classname)
        @configurator::get_infra_nodes_with_class(classname, @environment)
      end

      def get_settings_for_node(certname, settings)
        @configurator::read_hiera_classifier_overrides(certname, settings, @environment, @environmentpath)
      end

      def get_resources_for_node(certname)
        resources = {}
        node_facts = @configurator::read_node_facts(certname, @environment)
        resources['cpu'] = node_facts['processors']['count'].to_i
        resources['ram'] = (node_facts['memory']['system']['total_bytes'].to_i / 1024 / 1024).to_i
        resources
      end

      # Identify this infrastructure.

      def unknown_pe_infrastructure?
        @primary_masters.count.zero? || @pe_database_host.empty?
      end

      def monolithic?
        @console_hosts.count.zero? && @puppetdb_hosts.count.zero?
      end

      def with_ha?
        @replica_masters.count > 0
      end

      def with_compile_masters?
        @compile_masters.count > 0
      end

      def with_external_database?
        @external_database_hosts.count > 0
      end

      # Identify component(s) on node.

      def with_activemq?(certname)
        return false unless certname
        @hosts_with_amq_broker.count > 0 && @hosts_with_amq_broker.include?(certname)
      end

      def with_console?(certname)
        return false unless certname
        @hosts_with_console.count > 0 && @hosts_with_console.include?(certname)
      end

      def with_database?(certname)
        return false unless certname
        @hosts_with_database.count > 0 && @hosts_with_database.include?(certname)
      end

      def with_orchestrator?(certname)
        return false unless certname
        @hosts_with_orchestrator.count > 0 && @hosts_with_orchestrator.include?(certname)
      end

      def with_puppetdb?(certname)
        return false unless certname
        @hosts_with_puppetdb.count > 0 && @hosts_with_puppetdb.include?(certname)
      end

      def get_components_for_node(certname)
        components = {
          'activemq'     => with_activemq?(certname),
          'console'      => with_console?(certname),
          'database'     => with_database?(certname),
          'orchestrator' => with_orchestrator?(certname),
          'puppetdb'     => with_puppetdb?(certname)
        }
        components
      end

      # Identify configuration of node.

      def with_jruby9k_enabled?(certname)
        jr9kjar = '/opt/puppetlabs/server/apps/puppetserver/jruby-9k.jar'
        available = File.exist?(jr9kjar)
        setting = 'puppet_enterprise::master::puppetserver::jruby_9k_enabled'
        # Puppet::Util::Pe_conf::Recover.find_hiera_overrides() has issues in 2017.3.x.
        begin
          settings, _duplicates = get_settings_for_node(certname, [setting])
          enabled = settings[setting] != 'false'
        rescue StandardError
          enabled = false
        end
        Puppet.debug("jruby_9k_enabled: available: #{available} enabled: #{enabled}")
        available && enabled
      end

      # Output current settings based upon Classifier and Hiera data.

      def output_current_settings
        output_pe_infrastructure_error_and_exit if unknown_pe_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?)

        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @primary_masters.each do |certname|
          settings, duplicates = get_settings_for_node(certname, tunable_settings)
          output_node_settings('Primary Master', certname, settings, duplicates)
          available_jrubies += (settings['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || [resources['cpu'] - 1, 4].min)
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @replica_masters.each do |certname|
          settings, duplicates = get_settings_for_node(certname, tunable_settings)
          output_node_settings('Replica Master', certname, settings, duplicates)
        end

        unless monolithic?
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

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @external_database_hosts.each do |certname|
          settings, duplicates = get_settings_for_node(certname, tunable_settings)
          output_node_settings('External Database Host', certname, settings, duplicates)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        if with_compile_masters?
          available_jrubies = 0
          @compile_masters.each do |certname|
            resources = get_resources_for_node(certname)
            settings, duplicates = get_settings_for_node(certname, tunable_settings)
            output_node_settings('Compile Master', certname, settings, duplicates)
            available_jrubies += (settings['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || [resources['CPU'] - 1, 4].min)
          end
        end

        output_capacity_summary(available_jrubies)
      end

      # Calculate optimized settings based upon each node's set of services.

      def output_optimized_settings
        output_pe_infrastructure_error_and_exit if unknown_pe_infrastructure?
        create_output_directories
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?)

        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @primary_masters.each do |certname|
          resources = get_resources_for_node(certname)
          if ENV['TUNE_CPU']
            Puppet.debug("Using TUNE_CPU=#{ENV['TUNE_CPU']} for #{certname}")
            resources['cpu'] = ENV['TUNE_CPU'].to_i
          end
          if ENV['TUNE_RAM']
            Puppet.debug("Using TUNE_RAM=#{ENV['TUNE_RAM']} for #{certname}")
            resources['ram'] = ENV['TUNE_RAM'].to_i
          end
          output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
          configuration = {
            'is_monolithic_master' => monolithic?,
            'with_compile_masters' => with_compile_masters?,
            'with_jruby9k_enabled' => with_jruby9k_enabled?(certname),
          }
          components = get_components_for_node(certname)
          settings, totals = @calculator::calculate_master_settings(resources, configuration, components)
          output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
          collect_node(certname, 'Primary Master', resources, settings, totals)
          available_jrubies += (settings['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || [resources['cpu'] - 1, 4].min)
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @replica_masters.each do |certname|
          resources = get_resources_for_node(certname)
          output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
          configuration = {
            'is_monolithic_master' => monolithic?,
            'with_compile_masters' => with_compile_masters?,
            'with_jruby9k_enabled' => with_jruby9k_enabled?(certname),
          }
          components = get_components_for_node(certname)
          settings, totals = @calculator::calculate_master_settings(resources, configuration, components)
          output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
          collect_node(certname, 'Replica Master', resources, settings, totals)
        end

        unless monolithic?
          # Console Host: Specific to Split Infrastructures. By default, a list of one.
          @console_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_console_settings(resources)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
            collect_node(certname, 'Console Host', resources, settings, totals)
          end

          # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
          @puppetdb_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            components = get_components_for_node(certname)
            settings, totals = @calculator::calculate_puppetdb_settings(resources, components)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
            collect_node(certname, 'PuppetDB Host', resources, settings, totals)
          end
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @external_database_hosts.each do |certname|
          resources = get_resources_for_node(certname)
          output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
          settings, totals = @calculator::calculate_database_settings(resources)
          output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
          collect_node(certname, 'External Database Host', resources, settings, totals)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        if with_compile_masters?
          @compile_masters.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            configuration = {
              'is_monolithic_master' => false,
              'with_compile_masters' => true,
              'with_jruby9k_enabled' => with_jruby9k_enabled?(certname),
            }
            components = get_components_for_node(certname)
            settings, totals = @calculator::calculate_master_settings(resources, configuration, components)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty?
            collect_node(certname, 'Compile Master', resources, settings, totals)
            available_jrubies += (settings['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || [resources['cpu'] - 1, 4].min)
          end
        end

        # Output collected information.

        extract_common_optimized_settings

        @collected_nodes.each do |certname, properties|
          output_node_resources(certname, properties['profile'], properties['resources'])
          output_node_optimized_settings(certname, properties['settings'])
          output_node_optimized_settings_summary(certname, properties['totals'])
        end

        output_common_optimized_settings
        output_capacity_summary(available_jrubies)
        create_output_files
      end

      # Collect node for output.

      def collect_node(certname, profile, resources, settings, totals)
        properties = {
          'profile'   => profile,
          'resources' => resources,
          'settings'  => settings,
          'totals'    => totals,
        }
        @collected_nodes[certname] = properties
      end

      # Extract common settings for common.yaml from <certname>.yaml.

      def extract_common_optimized_settings
        return unless @option_common_settings
        nodes_with_setting = {}
        @collected_nodes.each do |certname, properties|
          properties['settings'].each do |setting, value|
            nodes_with_setting[setting] = {} unless nodes_with_setting.key?(setting)
            nodes_with_setting[setting][certname] = value
          end
        end
        nodes_with_setting.each do |setting, nodes|
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

      def output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_external_database)
        type = is_monolithic ? 'Monolithic' : 'Split'
        w_cm = with_compile_masters ? ' with Compile Masters' : ''
        w_ep = with_external_database ? ' with External Database' : ''
        output("### Puppet Infrastructure Summary: Found a #{type} Infrastructure#{w_cm}#{w_ep}\n\n")
      end

      # Output current information.

      def output_node_settings(profile, certname, settings, duplicates)
        if settings.empty?
          output("## Default settings found for #{profile} #{certname}\n\n")
          return
        end
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

      def output_node_optimized_settings_summary(certname, totals)
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

      def output_common_optimized_settings
        return unless @option_common_settings
        return if @common_settings.empty?
        output("## Specify the following optimized settings in Hiera in common.yaml\n\n")
        output(@common_settings.to_yaml)
        output("\n")
      end

      def output_capacity_summary(available_jrubies)
        run_interval = Puppet[:runinterval]
        active_nodes = @configurator::read_active_nodes
        report_limit = @calculator::calculate_run_sample(active_nodes, run_interval)
        average_compile_time = @configurator::read_average_compile_time(report_limit)
        maximum_nodes = @calculator::calculate_maximum_nodes(average_compile_time, available_jrubies, run_interval)
        minimum_jrubies = @calculator::calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
        output("### Puppet Infrastructure Capacity Summary: Found: Active Nodes: #{active_nodes}\n\n")
        output("## Given: Available JRubies: #{available_jrubies}, Agent Run Interval: #{run_interval} Seconds, Average Compile Time: #{average_compile_time} Seconds")
        output("## Estimate: a maximum of #{maximum_nodes} Active Nodes can be served by #{available_jrubies} Available JRubies")
        output("## Estimate: a minimum of #{minimum_jrubies} Available JRubies is required to serve #{active_nodes} Active Nodes\n\n")
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
    end
  end
end

# The following code replaces lib/puppet/face/infrastructure/tune.rb
#   allowing this class to be executed as a standalone script.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'optparse'
  require 'puppet'

  Puppet.initialize_settings
  Puppet::Util::Log.newdestination :console

  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: tune.rb [options]'
    opts.separator ''
    opts.separator 'Summary: Inspect infrastructure and output optimized settings'
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
    opts.on('--memory_per_jruby MB', 'Amount of RAM to allocate for each Puppet Server JRuby') do |me|
      options[:memory_per_jruby] = me.to_i
    end
    opts.on('--memory_reserved_for_os MB', 'Amount of RAM to reserve for the operating system') do |mo|
      options[:memory_reserved_for_os] = mo.to_i
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

  # The location of enterprise modules varies from version to version.

  enterprise_modules = ['pe_infrastructure', 'pe_install', 'pe_manager']
  env_mod = '/opt/puppetlabs/server/data/environments/enterprise/modules'
  ent_mod = '/opt/puppetlabs/server/data/enterprise/modules'
  enterprise_module_paths = [env_mod, ent_mod]
  enterprise_module_paths.each do |enterprise_module_path|
    next unless File.directory?(enterprise_module_path)
    enterprise_modules.each do |enterprise_module|
      enterprise_module_lib = "#{enterprise_module_path}/#{enterprise_module}/lib"
      next if $LOAD_PATH.include?(enterprise_module_lib)
      Puppet.debug("Adding #{enterprise_module} to LOAD_PATH: #{enterprise_module_lib}")
      $LOAD_PATH.unshift(enterprise_module_lib)
    end
  end

  require_relative 'tune/calculate'
  require_relative 'tune/configuration'

  Tune = PuppetX::Puppetlabs::Tune.new(options)

  if options[:current]
    Tune.output_current_settings
  else
    Tune.output_optimized_settings
  end
end
