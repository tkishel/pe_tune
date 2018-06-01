#!/opt/puppetlabs/puppet/bin/ruby

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

        if Puppet[:certname] != Puppet[:server]
          output_not_primary_master_and_exit
        end

        # PE-15116 results in Puppet[:environment] being set to 'enterprise' within the infrastructure face.
        @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new
        @configurator = PuppetX::Puppetlabs::Tune::Configuration.new

        @pe_database_host = @configurator.pe_conf_database_host

        @replica_masters = get_nodes_with_class('Primary_master_replica')
        @primary_masters = get_nodes_with_class('Certificate_authority') - @replica_masters
        @compile_masters = get_nodes_with_class('Master')   - @primary_masters - @replica_masters
        @console_hosts   = get_nodes_with_class('Console')  - @primary_masters - @replica_masters
        @puppetdb_hosts  = get_nodes_with_class('Puppetdb') - @primary_masters - @replica_masters
        @database_hosts  = get_nodes_with_class('Database') - @primary_masters - @replica_masters
      end

      # Interfaces to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover

      def get_nodes_with_class(classname)
        @configurator::get_infra_nodes_with_class(classname, @environment)
      end

      def get_settings_for_node(certname, settings)
        @configurator::read_hiera_classifier_overrides(certname, settings, @environment)
      end

      # Note: Allow override via ENV for testing.

      def get_resources_for_node(certname)
        resources = {}
        node_facts = @configurator::read_node_facts(certname, @environment)
        resources['cpu'] = node_facts['processors']['count'].to_i
        resources['ram'] = (node_facts['memory']['system']['total_bytes'].to_i / 1024 / 1024).to_i
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
          output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
          if is_monolithic
            settings, totals = @calculator::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          else
            settings, totals = @calculator::calculate_master_settings(resources, true, true)
          end
          output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
          collect_node(certname, 'Primary Master', resources, settings, totals)
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @replica_masters.each do |certname|
          resources = get_resources_for_node(certname)
          output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
          settings, totals = @calculator::calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
          collect_node(certname, 'Replica Master', resources, settings, totals)
        end

        unless is_monolithic
          # Console Host: Specific to Split Infrastructures. By default, a list of one.
          @console_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_master_settings(resources, false, false)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
            collect_node(certname, 'Compile Master', resources, settings, totals)
          end

          # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
          @puppetdb_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_puppetdb_settings(resources, with_external_postgresql)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
            collect_node(certname, 'PuppetDB Host', resources, settings, totals)
          end
        end

        # External PostgreSQL Host: Applicable to Monolithic and Split Infrastructures.
        if with_external_postgresql
          @pe_database_hosts.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_external_postgresql_settings(resources)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
            collect_node(certname, 'External PostgreSQL Host', resources, settings, totals)
          end
          if @database_hosts.count.zero?
            resources = get_resources_for_node(@pe_database_host)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_external_postgresql_settings(resources)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
            collect_node(@pe_database_host, 'External PostgreSQL Host', resources, settings, totals)
          end
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        if with_compile_masters
          @compile_masters.each do |certname|
            resources = get_resources_for_node(certname)
            output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
            settings, totals = @calculator::calculate_master_settings(resources, false, false)
            output_minimum_system_requirements_error_and_exit(certname) if settings.empty? || totals.empty?
            collect_node(certname, 'Compile Master', resources, settings, totals)
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

# The remainder of this file allows this class to be executed as a standalone script.
# TODO: Delete the remainder of this file prior to release of the module.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'optparse'
  require 'puppet'

  # The location of enterprise modules varies from version to version.

  enterprise_modules = ['pe_infrastructure', 'pe_install', 'pe_manager']
  ent_mod = '/opt/puppetlabs/server/data/enterprise/modules'
  env_mod = '/opt/puppetlabs/server/data/environments/enterprise/modules'
  enterprise_module_path = File.directory?(ent_mod) ? ent_mod : env_mod
  enterprise_modules.each do |enterprise_module|
    enterprise_module_lib = "#{enterprise_module_path}/#{enterprise_module}/lib"
    $LOAD_PATH.unshift(enterprise_module_lib) unless $LOAD_PATH.include?(enterprise_module_lib)
  end

  # The following code replaces lib/puppet/face/infrastructure/tune.rb

  require_relative 'tune/calculate'
  require_relative 'tune/configuration'

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
