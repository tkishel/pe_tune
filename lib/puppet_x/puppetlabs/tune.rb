#!/opt/puppetlabs/puppet/bin/ruby

require 'set'

# Notes:
#
# This script optimizes the settings documented in tuning_monolithic:
#   https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not optimize the following settings in puppetlabs-puppet_enterprise:
#   autovacuum_max_workers, autovacuum_work_mem, effective_cache_size, maintenance_work_mem, work_mem
#
# It accepts the following overrides via ENV:
#   export TEST_CPU=8; export TEST_RAM=16384;
# These are necessary to accomodate manual testing and pe_acceptance_tests/acceptance/tests/faces/infrastructure/tune.rb.

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

        if options[:current] && (options[:inventory] || options[:local])
          output_error_and_exit('The --current and (--inventory or --local) options are mutually exclusive')
          exit 1
        end

        if options[:inventory] && options[:local]
          output_error_and_exit('The --inventory and --local options are mutually exclusive')
        end

        @collected_nodes = {}
        @common_settings = {}
        @inventory = {}

        @tune_options = {}
        @tune_options[:common]    = options[:common]
        @tune_options[:estimate]  = options[:estimate]
        @tune_options[:force]     = options[:force]
        @tune_options[:hiera]     = options[:hiera]
        @tune_options[:inventory] = options[:inventory]
        @tune_options[:local]     = options[:local]

        calculate_options = {}
        calculate_options[:memory_per_jruby]       = options[:memory_per_jruby]
        calculate_options[:memory_reserved_for_os] = options[:memory_reserved_for_os]

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new(calculate_options)

        if @tune_options[:local]
          @inventory = read_inventory_local
          @pe_puppet_master_host = @inventory['roles']['puppet_master_host']
          @pe_database_host      = @inventory['profiles']['database'].first
        elsif @tune_options[:inventory]
          @inventory = read_inventory_file
          @pe_puppet_master_host = @inventory['roles']['puppet_master_host']
          @pe_database_host      = @inventory['profiles']['database'].first
        else
          # PE-15116 overrides environment and environmentpath in the infrastructure face.
          @environment = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
          @environmentpath = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environmentpath --section master').chomp
          @configurator = PuppetX::Puppetlabs::Tune::Configuration.new
          if @configurator::find_pe_conf_puppet_master_host != Puppet[:certname]
            output_error_and_exit('This command must be run on the Primary Master')
          end
          @pe_puppet_master_host = Puppet[:certname]
          @pe_database_host      = @configurator::find_pe_conf_database_host || Puppet[:certname]
        end

        # TODO: Reconcile primary_master and puppet_master_host.
        @hosts_with_primary_master         = get_nodes_with_class('primary_master')

        @hosts_with_primary_master_replica = get_nodes_with_class('primary_master_replica')
        @hosts_with_certificate_authority  = get_nodes_with_class('certificate_authority')
        @hosts_with_master                 = get_nodes_with_class('master')
        @hosts_with_compile_master         = get_nodes_with_class('compile_master')
        @hosts_with_console                = get_nodes_with_class('console')
        @hosts_with_puppetdb               = get_nodes_with_class('puppetdb')
        @hosts_with_database               = get_nodes_with_class('database')
        @hosts_with_amq_broker             = get_nodes_with_class('amq::broker')
        @hosts_with_orchestrator           = get_nodes_with_class('orchestrator')

        @hosts_with_m_or_cm = (@hosts_with_master + @hosts_with_compile_master).uniq

        @primary_masters         = [@pe_puppet_master_host]
        @replica_masters         = @hosts_with_primary_master_replica
        @compile_masters         = @hosts_with_m_or_cm  - @primary_masters - @replica_masters
        @console_hosts           = @hosts_with_console  - @primary_masters - @replica_masters
        @puppetdb_hosts          = @hosts_with_puppetdb - @primary_masters - @replica_masters - @compile_masters
        @external_database_hosts = @hosts_with_database - @primary_masters - @replica_masters - @compile_masters - @puppetdb_hosts
      end

      # Valid infrastructure 'roles' and 'profiles'.
      # https://github.com/puppetlabs/puppetlabs-pe_infrastructure/blob/irving/lib/puppet_x/puppetlabs/meep/defaults.rb

      def default_inventory_roles
        {
          'puppet_master_host' => nil,
          'console_host'       => nil,
          'puppetdb_host'      => nil,
          'database_host'      => nil,
        }
      end

      def default_inventory_profiles
        {
          'primary_master_replica' => [].to_set,
          'certificate_authority'  => [].to_set,
          'master'                 => [].to_set,
          'compile_master'         => [].to_set,
          'console'                => [].to_set,
          'puppetdb'               => [].to_set,
          'database'               => [].to_set,
          'amq::broker'            => [].to_set, # Deprecated in PE 2018+
          'orchestrator'           => [].to_set,
        }
      end

      # Convert infrastructure 'roles' to infrastructure 'profiles' using sets to eliminate duplicates.

      def convert_inventory_roles_to_profiles(inventory)
        if inventory['roles']['puppet_master_host']
          Puppet.debug("Converting puppet_master_host role to profiles for: #{inventory['roles']['puppet_master_host']}")
          inventory['profiles']['certificate_authority'] << inventory['roles']['puppet_master_host'] if inventory['profiles']['certificate_authority'].count.zero?
          inventory['profiles']['master']                << inventory['roles']['puppet_master_host']
          inventory['profiles']['console']               << inventory['roles']['puppet_master_host'] unless inventory['roles']['console_host']
          inventory['profiles']['puppetdb']              << inventory['roles']['puppet_master_host'] unless inventory['roles']['puppetdb_host']
          inventory['profiles']['database']              << inventory['roles']['puppet_master_host'] unless inventory['roles']['database_host']
          inventory['profiles']['amq::broker']           << inventory['roles']['puppet_master_host'] # Deprecated in PE 2018+
          inventory['profiles']['orchestrator']          << inventory['roles']['puppet_master_host']
        end
        if inventory['roles']['console_host']
          Puppet.debug("Converting console_host role to profiles for: #{inventory['roles']['console_host']}")
          inventory['profiles']['console'] << inventory['roles']['console_host']
        end
        if inventory['roles']['puppetdb_host']
          Puppet.debug("Converting puppetdb_host role to profiles for: #{inventory['roles']['puppetdb_host']}")
          inventory['profiles']['puppetdb'] << inventory['roles']['puppetdb_host']
          inventory['profiles']['database'] << inventory['roles']['puppetdb_host'] unless inventory['roles']['database_host']
        end
        if inventory['roles']['database_host']
          Puppet.debug("Converting ['roles']['database_host'] to profiles for: #{inventory['roles']['database_host']}")
          inventory['profiles']['database'] << inventory['roles']['database_host']
        end
        output_error_and_exit('The inventory file is limited to one primary_master_replica') if inventory['profiles']['primary_master_replica'].count > 1
        output_error_and_exit('The inventory file is limited to one certificate_authority')  if inventory['profiles']['certificate_authority'].count > 1
        output_error_and_exit('The inventory file is limited to one console')                if inventory['profiles']['console'].count > 1
        inventory
      end

      # Use the local system to define a monolithic infrastructure master node.
      # This eliminates the dependency upon PuppetDB to query node resources and classes.

      def read_inventory_local
        Puppet.debug('Querying the local system to define a monolithic infrastructure master node')
        hostname = Puppet::Util::Execution.execute('hostname -f').chomp
        nodes = {
          hostname => {
            'resources' => {
              'cpu' => Puppet::Util::Execution.execute('nproc --all').chomp,
              'ram' => Puppet::Util::Execution.execute('free -b| grep Mem').chomp.split(' ')[1],
            }
          }
        }
        Puppet.debug("Found resources on the local system: #{nodes}")
        roles = default_inventory_roles
        profiles = default_inventory_profiles
        roles['puppet_master_host'] = hostname
        inventory = {
          'nodes'    => nodes,
          'roles'    => roles,
          'profiles' => profiles,
        }
        convert_inventory_roles_to_profiles(inventory)
      end

      # Use an inventory file to define infrastructure nodes.
      # This eliminates the dependency upon PuppetDB to query node resources and classes.

      def read_inventory_file
        yaml_file = @tune_options[:inventory]
        Puppet.debug("Using the inventory file #{yaml_file} to define infrastructure nodes")
        roles = default_inventory_roles
        profiles = default_inventory_profiles
        output_error_and_exit("The inventory file #{yaml_file} does not exist") unless File.exist?(yaml_file)
        begin
          yaml_inventory = YAML.load_file(yaml_file)
        rescue StandardError
          yaml_inventory = {}
        end
        output_error_and_exit('The inventory file does not contain a nodes hash') unless yaml_inventory['nodes']
        output_error_and_exit('The inventory file does not contain a roles hash') unless yaml_inventory['roles']
        output_error_and_exit('The inventory file does not contain a roles hash with a puppet_master_host key/value') unless yaml_inventory['roles']['puppet_master_host']
        yaml_inventory['profiles'] = [] unless yaml_inventory['profiles']
        inventory = {
          'nodes'    => yaml_inventory['nodes'],
          'roles'    => roles.merge(yaml_inventory['roles']),
          'profiles' => profiles.merge(yaml_inventory['profiles']),
        }
        convert_inventory_roles_to_profiles(inventory)
      end

      # Interface to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover
      # Override when using an inventory file.

      def get_nodes_with_class(classname)
        if @inventory['profiles']
          # Profile key names are downcased in inventory.
          class_name = classname.downcase
          nodes_with_class = @inventory['profiles'][class_name].to_a
          Puppet.debug("Found class in inventory: #{class_name}: #{nodes_with_class}")
          nodes_with_class
        else
          # Profile key names are capitalized in PuppetDB.
          class_name = classname.split('::').map(&:capitalize).join('::')
          @configurator::get_infra_nodes_with_class(class_name, @environment)
        end
      end

      # Interface to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover
      # Override when using an inventory file, or when testing with environment variables.

      def get_resources_for_node(certname)
        resources = {}
        if @inventory['nodes']
          if @inventory['nodes'][certname] && @inventory['nodes'][certname]['resources']
            node_facts = @inventory['nodes'][certname]['resources']
            resources['cpu'] = node_facts['cpu'].to_i
            resources['ram'] = (node_facts['ram'].to_i / 1024 / 1024).to_i
            Puppet.debug("Found node in inventory: #{certname} with CPU: #{resources['cpu']} and RAM: #{resources['ram']}")
          else
            output_error_and_exit("Inventory file does not contain resources for node #{certname}")
          end
        else
          node_facts = @configurator::read_node_facts(certname, @environment)
          resources['cpu'] = node_facts['processors']['count'].to_i
          resources['ram'] = (node_facts['memory']['system']['total_bytes'].to_i / 1024 / 1024).to_i
        end
        if ENV['TEST_CPU']
          Puppet.debug("Using TEST_CPU=#{ENV['TEST_CPU']} for #{certname}")
          resources['cpu'] = ENV['TEST_CPU'].to_i
        end
        if ENV['TEST_RAM']
          Puppet.debug("Using TEST_RAM=#{ENV['TEST_RAM']} for #{certname}")
          resources['ram'] = ENV['TEST_RAM'].to_i
        end
        resources
      end

      # Interface to Puppet::Util::Pe_conf and Puppet::Util::Pe_conf::Recover

      def get_settings_for_node(certname, settings)
        @configurator::read_hiera_classifier_overrides(certname, settings, @environment, @environmentpath)
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
        Puppet.debug("jruby_9k_enabled: available: #{available}, enabled: #{enabled}")
        available && enabled
      end

      # Output current settings based upon Classifier and Hiera data.

      def output_current_settings
        output_pe_infrastructure_error_and_exit if unknown_pe_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?)

        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @primary_masters.each do |certname|
          resources = get_resources_for_node(certname)
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

        output_estimated_capacity(available_jrubies)
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
        output_estimated_capacity(available_jrubies)
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
        return unless @tune_options[:common]
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
        return unless @tune_options[:hiera]
        hiera_directory = @tune_options[:hiera]
        hiera_subdirectory = "#{hiera_directory}/nodes"
        return if File.directory?(hiera_directory) && File.directory?(hiera_subdirectory)
        Dir.mkdir(hiera_directory) unless File.directory?(hiera_directory)
        output_error_and_exit("Unable to create output directory: #{hiera_directory}") unless File.directory?(hiera_directory)
        Dir.mkdir(hiera_subdirectory) unless File.directory?(hiera_subdirectory)
        output_error_and_exit("Unable to create output directory: #{hiera_subdirectory}") unless File.directory?(hiera_subdirectory)
      end

      # Output Hiera YAML files.

      def create_output_files
        return unless @tune_options[:hiera]
        return if @collected_nodes.empty?
        @collected_nodes.each do |certname, properties|
          next if properties['settings'].empty?
          output_file = "#{@tune_options[:hiera]}/nodes/#{certname}.yaml"
          File.write(output_file, properties['settings'].to_yaml)
          output("## Wrote Hiera YAML file: #{output_file}\n\n")
        end
        return if @common_settings.empty?
        output_file = "#{@tune_options[:hiera]}/common.yaml"
        File.write(output_file, @common_settings.to_yaml)
      end

      # Verify minimum system requirements.

      def meets_minimum_system_requirements?(resources)
        return true if @tune_options[:force]
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
          output("## JVM Summary: Using #{mb_per_puppetserver_jruby} MB per Puppet Server JRuby for #{certname}")
        end
        output("\n")
      end

      def output_common_optimized_settings
        return unless @tune_options[:common]
        return if @common_settings.empty?
        output("## Specify the following optimized settings in Hiera in common.yaml\n\n")
        output(@common_settings.to_yaml)
        output("\n")
      end

      def output_estimated_capacity(available_jrubies)
        return unless @tune_options[:estimate]
        run_interval = Puppet[:runinterval]
        active_nodes = @configurator::read_active_nodes
        report_limit = @calculator::calculate_run_sample(active_nodes, run_interval)
        average_compile_time = @configurator::read_average_compile_time(report_limit)
        maximum_nodes = @calculator::calculate_maximum_nodes(average_compile_time, available_jrubies, run_interval)
        minimum_jrubies = @calculator::calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
        output("### Puppet Infrastructure Estimated Capacity Summary: Found: Active Nodes: #{active_nodes}\n\n")
        output("## Given: Available JRubies: #{available_jrubies}, Agent Run Interval: #{run_interval} Seconds, Average Compile Time: #{average_compile_time} Seconds")
        output("## Estimate: a maximum of #{maximum_nodes} Active Nodes can be served by #{available_jrubies} Available JRubies")
        output("## Estimate: a minimum of #{minimum_jrubies} Available JRubies is required to serve #{active_nodes} Active Nodes\n\n")
      end

      # Output error and exit.

      def output_error_and_exit(message)
        Puppet.err(message)
        exit 1
      end

      def output_pe_infrastructure_error_and_exit
        Puppet.err('Puppet Infrastructure Summary: Unknown Infrastructure')
        Puppet.err('Unable to find a Primary Master via a PuppetDB query')
        Puppet.err('Verify PE Infrastructure node groups in the Console')
        Puppet.err('Rerun this command with --debug for more information')
        exit 1
      end

      def output_minimum_system_requirements_error_and_exit(certname)
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
  require 'yaml'

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
    options[:estimate] = false
    opts.on('--estimate', 'Output estimated capacity summary') do
      options[:estimate] = true
    end
    options[:force] = false
    opts.on('--force', 'Do not enforce minimum system requirements') do
      options[:force] = true
    end
    opts.on('--hiera DIRECTORY', 'Output Hiera YAML files to the specified directory') do |hi|
      options[:hiera] = hi
    end
    opts.on('--inventory FILE', 'Use a YAML file to define infrastructure nodes') do |no|
      options[:inventory] = no
    end
    options[:local] = false
    opts.on('--local', 'Query the local system to define a monolithic infrastructure master node') do
      options[:local] = true
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
