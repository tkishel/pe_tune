#!/opt/puppetlabs/puppet/bin/ruby

# Notes:
#
# This script optimizes the settings documented in tuning_monolithic:
#   https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not optimize the following settings in puppetlabs-puppet_enterprise:
#   puppet_enterprise::profile::database::autovacuum_max_workers
#   puppet_enterprise::profile::database::autovacuum_work_mem
#   puppet_enterprise::profile::database::maintenance_work_mem
#   puppet_enterprise::profile::database::effective_cache_size
#   puppet_enterprise::profile::database::work_mem
#
# It accepts the following overrides via ENV:
#   export TEST_CPU=8; export TEST_RAM=16384;
# These are necessary to accomodate manual testing and pe_acceptance_tests/acceptance/tests/faces/infrastructure/tune.rb.

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current or calculate optimized settings.
    class Tune
      # List of settings used by this module.
      def tunable_param_names
        [
          'puppet_enterprise::master::puppetserver::jruby_max_active_instances',
          'puppet_enterprise::master::puppetserver::reserved_code_cache',
          'puppet_enterprise::profile::amq::broker::heap_mb',
          'puppet_enterprise::profile::console::java_args',
          'puppet_enterprise::profile::database::shared_buffers',
          'puppet_enterprise::profile::database::max_connections',
          'puppet_enterprise::profile::master::java_args',
          'puppet_enterprise::profile::orchestrator::java_args',
          'puppet_enterprise::profile::puppetdb::java_args',
          'puppet_enterprise::puppetdb::command_processing_threads',
        ]
      end

      # List of classes used by this module.

      def tunable_class_names
        [
          'certificate_authority',
          'master',
          'console',
          'puppetdb',
          'database',
          'amq::broker',
          'orchestrator',
          'primary_master',
          'primary_master_replica',
          'enabled_primary_master_replica',
          'compile_master',
        ]
      end

      # Initialize this module class.

      def initialize(options)
        # Disable this method when unit testing the supporting methods.
        return if options[:unit_test]

        if options[:current] && (options[:inventory] || options[:local])
          output_error_and_exit('The --current and (--inventory or --local) options are mutually exclusive')
        end

        if options[:inventory] && options[:local]
          output_error_and_exit('The --inventory and --local options are mutually exclusive')
        end

        # Properties for each node.
        @collected_nodes = {}

        # Settings common to all nodes.
        @collected_settings_common = {}

        # Nodes with classes from inventory or PuppetDB.
        @nodes_with_class = {}

        # Nodes with role.
        @nodes_with_role = {}

        # Options specific to this Tune class.
        @options = {}
        @options[:common]    = options[:common]
        @options[:estimate]  = options[:estimate]
        @options[:force]     = options[:force]
        @options[:hiera]     = options[:hiera]
        @options[:inventory] = options[:inventory]
        @options[:local]     = options[:local]

        # Options specific to the Calculate class.
        calculate_options = {}
        calculate_options[:memory_per_jruby]       = string_to_megabytes(options[:memory_per_jruby])
        calculate_options[:memory_reserved_for_os] = string_to_megabytes(options[:memory_reserved_for_os])

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new(calculate_options)

        # PE-15116 overrides environment and environmentpath in the 'puppet infrastructure' face.
        # Original values are required by some methods interfacing with PuppetX::Puppetlabs::Tune::Configuration.
        @environment     = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environment --section master').chomp
        @environmentpath = Puppet::Util::Execution.execute('/opt/puppetlabs/puppet/bin/puppet config print environmentpath --section master').chomp

        @configurator = PuppetX::Puppetlabs::Tune::Configuration.new
        @inventory = PuppetX::Puppetlabs::Tune::Inventory.new

        # If using the local system or a file as inventory, read inventory and convert inventory roles to classes.
        if @options[:local] || @options[:inventory]
          @inventory::read_inventory_from_local_system if @options[:local]
          @inventory::read_inventory_from_inventory_file(@options[:inventory]) if @options[:inventory]
          output_error_and_exit('Unable to read Inventory') if @inventory::nodes.empty? || @inventory::classes.empty?
        end

        # Query PuppetDB (or inventory) for classes and cache the results.
        tunable_class_names.each do |classname|
          collect_nodes_with_class(classname)
        end

        # Mappings vary between roles, profiles, and classes.
        # See: https://github.com/puppetlabs/puppetlabs-pe_infrastructure/blob/irving/lib/puppet_x/puppetlabs/meep/defaults.rb

        replica_masters = (@nodes_with_class['primary_master_replica'] + @nodes_with_class['enabled_primary_master_replica']).uniq
        primary_masters = (@nodes_with_class['certificate_authority']  + @nodes_with_class['primary_master']).uniq
        masters_and_compile_masters = (@nodes_with_class['master'] + @nodes_with_class['compile_master']).uniq

        @nodes_with_role['replica_masters'] = replica_masters
        @nodes_with_role['primary_masters'] = primary_masters               - @nodes_with_role['replica_masters']
        @nodes_with_role['compile_masters'] = masters_and_compile_masters   - @nodes_with_role['primary_masters'] - @nodes_with_role['replica_masters']
        @nodes_with_role['console_hosts']   = @nodes_with_class['console']  - @nodes_with_role['primary_masters'] - @nodes_with_role['replica_masters']
        @nodes_with_role['puppetdb_hosts']  = @nodes_with_class['puppetdb'] - @nodes_with_role['primary_masters'] - @nodes_with_role['replica_masters'] - @nodes_with_role['compile_masters']
        @nodes_with_role['database_hosts']  = @nodes_with_class['database'] - @nodes_with_role['primary_masters'] - @nodes_with_role['replica_masters'] - @nodes_with_role['compile_masters'] - @nodes_with_role['puppetdb_hosts']

        if options[:current] && @nodes_with_role['replica_masters'].include?(Puppet[:certname])
          output_error_and_exit('The --current option is limited to running on the Primary Master')
        end
      end

      #
      # Interfaces
      #

      # Interface to PuppetX::Puppetlabs::Tune::Configuration and ::Inventory

      def collect_nodes_with_class(classname)
        if @inventory::classes.any?
          Puppet.debug _('Using Inventory for collect_nodes_with_class')
          # Key names are downcased in inventory.
          class_name = classname.downcase
          @nodes_with_class[classname] = @inventory::classes[class_name].to_a
        else
          Puppet.debug _('Using PuppetDB for collect_nodes_with_class')
          # Key names are capitalized in PuppetDB.
          class_name = classname.split('::').map(&:capitalize).join('::')
          @nodes_with_class[classname] = @configurator::get_infra_nodes_with_class(class_name, @environment)
        end
      end

      # Interface to PuppetX::Puppetlabs::Tune::Configuration and ::Inventory
      # Override when testing with environment variables.

      def get_resources_for_node(certname)
        resources = {}
        if @inventory::nodes.any?
          Puppet.debug _('Using Inventory for get_resources_for_node')
          output_error_and_exit("Cannot read node: #{certname}") unless @inventory::nodes[certname] && @inventory::nodes[certname]['resources']
          node_facts = @inventory::nodes[certname]['resources']
          output_error_and_exit("Cannot read resources for node: #{certname}") unless node_facts['cpu'] && node_facts['ram']
          resources['cpu'] = node_facts['cpu'].to_i
          resources['ram'] = string_to_bytes(node_facts['ram']).to_i
        else
          Puppet.debug _('Using PuppetDB for get_resources_for_node')
          node_facts = @configurator::get_node_facts(certname, @environment)
          output_error_and_exit("Cannot query resources for node: #{certname}") unless node_facts['processors'] && node_facts['memory']
          resources['cpu'] = node_facts['processors']['count'].to_i
          resources['ram'] = node_facts['memory']['system']['total_bytes'].to_i
        end
        resources['ram'] = (resources['ram'] / 1024 / 1024).to_i
        if ENV['TEST_CPU']
          Puppet.debug _("Using TEST_CPU=%{cpu} for %{certname}") % { cpu: ENV['TEST_CPU'], certname: certname }
          resources['cpu'] = ENV['TEST_CPU'].to_i
        end
        if ENV['TEST_RAM']
          Puppet.debug _("Using TEST_RAM=%{ram} for %{certname}") % { ram: ENV['TEST_RAM'], certname: certname }
          resources['ram'] = ENV['TEST_RAM'].to_i
        end
        resources
      end

      # Interface to PuppetX::Puppetlabs::Tune::Configuration

      def get_current_settings_for_node(certname, setting_names)
        @configurator::get_hiera_classifier_settings(certname, setting_names, @environment, @environmentpath)
      end

      #
      # Identify
      #

      # Identify infrastructure.

      def unknown_infrastructure?
        @nodes_with_role['primary_masters'].count.zero?
      end

      def monolithic?
        @nodes_with_role['console_hosts'].count.zero? && @nodes_with_role['puppetdb_hosts'].count.zero?
      end

      def with_ha?
        @nodes_with_role['replica_masters'].count > 0
      end

      def with_compile_masters?
        @nodes_with_role['compile_masters'].count > 0
      end

      def with_external_database?
        @nodes_with_role['database_hosts'].count > 0
      end

      def with_local_and_external_databases?
        primary_and_replica_masters_count = @nodes_with_role['primary_masters'].count + @nodes_with_role['replica_masters'].count
        @nodes_with_class['database'].count == (2 * primary_and_replica_masters_count)
      end

      def with_puppetdb_on_all_masters?
        primary_and_replica_masters_count = @nodes_with_role['primary_masters'].count + @nodes_with_role['replica_masters'].count
        @nodes_with_class['puppetdb'].count == (primary_and_replica_masters_count + @nodes_with_role['compile_masters'].count)
      end

      # Identify infrastructure node.

      def monolithic_master?(certname)
        monolithic? && @nodes_with_role['primary_masters'].include?(certname)
      end

      def replica_master?(certname)
        monolithic? && @nodes_with_role['replica_masters'].include?(certname)
      end

      def compile_master?(certname)
        @nodes_with_role['compile_masters'].include?(certname)
      end

      # Monolithic with or without HA
      # With PE Database Hosts (aka PostgreSQL Hosts) for pe-puppetdb on one host and the other databases on another
      # With Compile Masters with PuppetDB

      def extra_large?
        return false unless monolithic?
        return false unless with_compile_masters?
        with_local_and_external_databases? && with_puppetdb_on_all_masters?
      end

      # Identify class on a node.

      def node_with_class?(certname, classname)
        return false unless certname && classname
        @nodes_with_class[classname].count > 0 && @nodes_with_class[classname].include?(certname)
      end

      # Identify tunable classes on a node.

      def get_tunable_classes_for_node(certname)
        classes = {}
        tunable_class_names.each do |classname|
          classes[classname] = node_with_class?(certname, classname)
        end
        classes
      end

      # Identify JRuby version on a node.

      def with_jruby9k_enabled?(certname)
        return false if Gem::Version.new(Puppet.version) < Gem::Version.new('5.5.1') # <  2018.1
        return true if Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0') # >= 2019.0
        jr9kjar = '/opt/puppetlabs/server/apps/puppetserver/jruby-9k.jar'
        available = File.exist?(jr9kjar)
        return false unless available
        setting = 'puppet_enterprise::master::puppetserver::jruby_9k_enabled'
        # Do not query PuppetDB when using inventory, instead return the default.
        return true if @inventory::nodes.any?
        settings = get_current_settings_for_node(certname, [setting])
        return false unless settings['params'].key?(setting)
        enabled = settings['params'][setting] != 'false'
        Puppet.debug _("jruby_9k_enabled: available: %{available}, enabled: %{enabled}") % { available: available, enabled: enabled }
        available && enabled
      end

      # Identify available JRubies on a node.

      def available_jrubies_for_node(certname, settings)
        default_jrubies = [get_resources_for_node(certname)['cpu'] - 1, 4].min
        settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || default_jrubies
      end

      #
      # Output
      #

      # Output current settings for each infrastructure node based upon Classifier and Hiera data.

      def output_current_settings
        output_pe_infrastructure_error_and_exit if unknown_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?, extra_large?)

        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'Primary Master', settings)
          available_jrubies += available_jrubies_for_node(certname, settings) unless with_compile_masters?
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @nodes_with_role['replica_masters'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'Replica Master', settings)
        end

        # Console Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['console_hosts'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'Console Host', settings)
        end

        # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['puppetdb_hosts'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'PuppetDB Host', settings)
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['database_hosts'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'External Database Host', settings)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['compile_masters'].each do |certname|
          settings = get_current_settings_for_node(certname, tunable_param_names)
          output_current_settings_for_node_with_role(certname, 'Compile Master', settings)
          available_jrubies += available_jrubies_for_node(certname, settings)
        end

        output_estimated_capacity(available_jrubies)
      end

      # Output optimized settings for each infrastructure node based upon each node's set of services.

      def output_optimized_settings
        output_pe_infrastructure_error_and_exit if unknown_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?, extra_large?)

        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_node_with_role(certname, 'Primary Master', node)
          available_jrubies += available_jrubies_for_node(certname, node['settings']) unless with_compile_masters?
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @nodes_with_role['replica_masters'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_node_with_role(certname, 'Replica Master', node)
        end

        # Console Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['console_hosts'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_console_settings(node)
          collect_node_with_role(certname, 'Console Host', node)
        end

        # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['puppetdb_hosts'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_puppetdb_settings(node)
          collect_node_with_role(certname, 'PuppetDB Host', node)
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['database_hosts'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_database_settings(node)
          collect_node_with_role(certname, 'External Database Host', node)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['compile_masters'].each do |certname|
          node = get_configuration_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_node_with_role(certname, 'Compile Master', node)
          available_jrubies += available_jrubies_for_node(certname, node['settings'])
        end

        # Output collected information.

        collect_optimized_settings_common_to_all_nodes
        @collected_nodes.each do |certname, properties|
          output_optimized_settings_for_collected_node(certname, properties)
        end
        output_common_settings
        output_estimated_capacity(available_jrubies)
        output_settings_to_files
      end

      # Return configuration for a node.

      def get_configuration_for_node(certname)
        node = {}
        resources = get_resources_for_node(certname)
        output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
        node['certname'] = certname,
        node['classes'] = get_tunable_classes_for_node(certname)
        node['infrastructure'] = {
          'is_monolithic'        => monolithic?,
          'with_compile_masters' => with_compile_masters?,
          'with_extra_large'     => extra_large?,
        }
        node['resources'] = resources
        node['type'] = {
          'is_monolithic_master' => monolithic_master?(certname),
          'is_replica_master'    => replica_master?(certname),
          'is_compile_master'    => compile_master?(certname),
          'with_jruby9k_enabled' => with_jruby9k_enabled?(certname),
        }
        node
      end

      # Collect node for output to <certname>.yaml.

      def collect_node_with_role(certname, role, node)
        output_minimum_system_requirements_error_and_exit(certname) unless node['settings']
        properties = {
          'resources' => node['resources'],
          'role'      => role,
          'settings'  => node['settings'],
        }
        @collected_nodes[certname] = properties
      end

      # Extract common settings for common.yaml from <certname>.yaml.

      def collect_optimized_settings_common_to_all_nodes
        return unless @options[:common]
        nodes_with_param = {}
        @collected_nodes.each do |certname, properties|
          properties['settings']['params'].each do |param_name, param_value|
            nodes_with_param[param_name] = {} unless nodes_with_param.key?(param_name)
            nodes_with_param[param_name][certname] = param_value
          end
        end
        nodes_with_param.each do |param_name, nodes|
          next unless nodes.values.uniq.length == 1
          @collected_settings_common[param_name] = nodes.values[0]
          nodes.each do |certname, _value|
            @collected_nodes[certname]['settings']['params'].delete(param_name)
          end
        end
      end

      # Output Hiera YAML files.

      def output_settings_to_files
        return unless @options[:hiera]
        hiera_directory = @options[:hiera]
        hiera_subdirectory = "#{hiera_directory}/nodes"
        return if File.directory?(hiera_directory) && File.directory?(hiera_subdirectory)
        Dir.mkdir(hiera_directory) unless File.directory?(hiera_directory)
        output_error_and_exit("Unable to create output directory: #{hiera_directory}") unless File.directory?(hiera_directory)
        Dir.mkdir(hiera_subdirectory) unless File.directory?(hiera_subdirectory)
        output_error_and_exit("Unable to create output directory: #{hiera_subdirectory}") unless File.directory?(hiera_subdirectory)
        @collected_nodes.each do |certname, properties|
          next if properties['settings']['params'].empty?
          output_file = "#{@options[:hiera]}/nodes/#{certname}.yaml"
          File.write(output_file, properties['settings']['params'].to_yaml)
          output("## Wrote Hiera YAML file: #{output_file}\n\n")
        end
        return if @collected_settings_common.empty?
        output_file = "#{@options[:hiera]}/common.yaml"
        File.write(output_file, @collected_settings_common.to_yaml)
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

      def output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_external_database, with_extra_large)
        type = is_monolithic ? 'Monolithic' : 'Split'
        w_cm = with_compile_masters ? ' with Compile Masters' : ''
        w_ep = with_external_database ? ' with External Database' : ''
        w_xl = with_extra_large ? ' with XL' : ''
        output("### Puppet Infrastructure Summary: Found a #{type} Infrastructure#{w_cm}#{w_ep}#{w_xl}\n\n")
      end

      # Output current information for a node.

      def output_current_settings_for_node_with_role(certname, role, settings)
        if settings['params'].empty?
          output("## Found default settings for #{role} #{certname}\n\n")
        else
          output("## Found defined settings for #{role} #{certname}\n\n")
          output_data(JSON.pretty_generate(settings['params']))
          output("\n")
        end
        unless settings['duplicates'].count.zero?
          output("## Found duplicate defined settings in Hiera and in the Classifier (Console):\n\n")
          output_data(settings['duplicates'].join("\n"))
          output("\n")
          output("## Define settings in Hiera (preferred) or the Classifier, but not both.\n")
          output("## Note that Hiera includes settings defined in pe.conf.\n\n")
        end
      end

      # Output optimized information for a node.

      def output_optimized_settings_for_collected_node(certname, node)
        output("## Found: #{node['resources']['cpu']} CPU(s) / #{node['resources']['ram']} MB RAM for #{node['role']} #{certname}")
        unless node['settings']['params'].empty?
          output("## Specify the following optimized settings in Hiera in nodes/#{certname}.yaml\n\n")
          output_data(node['settings']['params'].to_yaml)
        end
        unless node['settings']['totals'].empty?
          if node['settings']['totals']['CPU']
            total = node['settings']['totals']['CPU']['total']
            used = node['settings']['totals']['CPU']['used']
            free = total - used
            output("## CPU Summary: Total/Used/Free: #{total}/#{used}/#{free} for #{certname}")
          end
          if node['settings']['totals']['RAM']
            total = node['settings']['totals']['RAM']['total']
            used = node['settings']['totals']['RAM']['used']
            free = total - used
            output("## RAM Summary: Total/Used/Free: #{total}/#{used}/#{free} for #{certname}")
          end
          if node['settings']['totals']['MB_PER_JRUBY']
            mb_per_puppetserver_jruby = node['settings']['totals']['MB_PER_JRUBY']
            output("## JVM Summary: Using #{mb_per_puppetserver_jruby} MB per Puppet Server JRuby for #{certname}")
          end
        end
        output("\n")
      end

      def output_common_settings
        return unless @options[:common]
        return if @collected_settings_common.empty?
        output("## Specify the following optimized settings in Hiera in common.yaml\n\n")
        output(@collected_settings_common.to_yaml)
        output("\n")
      end

      def output_estimated_capacity(available_jrubies)
        return unless @options[:estimate]
        run_interval = Puppet[:runinterval]
        active_nodes = @configurator::count_active_nodes
        report_limit = @calculator::calculate_run_sample(active_nodes, run_interval)
        average_compile_time = @configurator::get_average_compile_time(report_limit)
        maximum_nodes = @calculator::calculate_maximum_nodes(average_compile_time, available_jrubies, run_interval)
        minimum_jrubies = @calculator::calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
        output("### Puppet Infrastructure Estimated Capacity Summary: Found: Active Nodes: #{active_nodes}\n\n")
        output("## Given: Available JRubies: #{available_jrubies}, Agent Run Interval: #{run_interval} Seconds, Average Compile Time: #{average_compile_time} Seconds")
        output("## Estimate: a maximum of #{maximum_nodes} Active Nodes can be served by #{available_jrubies} Available JRubies")
        output("## Estimate: a minimum of #{minimum_jrubies} Available JRubies is required to serve #{active_nodes} Active Nodes")
        output('## Note that Available JRubies does not include the Primary Master when using Compile Masters') if with_compile_masters?
        output("\n")
      end

      # Output error and exit.

      def output_error_and_exit(message)
        Puppet.err(message)
        exit 1
      end

      def output_pe_infrastructure_error_and_exit
        Puppet.err _('Puppet Infrastructure Summary: Unknown Infrastructure')
        Puppet.err _('Unable to find a Primary Master via a PuppetDB query')
        Puppet.err _('Verify PE Infrastructure node groups in the Console')
        Puppet.err _('Rerun this command with --debug for more information')
        exit 1
      end

      def output_minimum_system_requirements_error_and_exit(certname)
        Puppet.err _("%{certname} does not meet the minimum system requirements to optimize its settings") % { certname: certname }
        exit 1
      end

      #
      # Utilities
      #

      # Verify minimum system requirements.

      def meets_minimum_system_requirements?(resources)
        return true if @options[:force]
        resources['cpu'] >= 4 && resources['ram'] >= 8192
      end

      # Convert (for example) 16, 16g, 16384m, 16777216k, or 17179869184b to 17179869184.

      def string_to_bytes(s, default_units = 'g')
        return 0 if s.nil?
        matches = %r{(\d+)\s*(\w?)}.match(s.to_s)
        output_error_and_exit("Unable to convert #{s} to bytes") if matches.nil?
        value = matches[1].to_f
        units = matches[2].empty? ? default_units : matches[2].downcase
        case units
        when 'b' then return value.to_i
        when 'k' then return (value * (1 << 10)).to_i
        when 'm' then return (value * (1 << 20)).to_i
        when 'g' then return (value * (1 << 30)).to_i
        else
          output_error_and_exit("Unable to convert #{s} to bytes, valid units are: b, k, m, g")
        end
      end

      # Convert (for example) 1g, 1024, 1024m to 1024.

      def string_to_megabytes(s, default_units = 'm')
        return 0 if s.nil?
        matches = %r{(\d+)\s*(\w?)}.match(s.to_s)
        output_error_and_exit("Unable to convert #{s} to megabytes") if matches.nil?
        value = matches[1].to_f
        units = matches[2].empty? ? default_units : matches[2].downcase
        case units
        when 'm' then return value.to_i
        when 'g' then return (value * (1 << 10)).to_i
        else
          output_error_and_exit("Unable to convert #{s} to megabytes, valid units are: m, g")
        end
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
    opts.separator 'Summary: Inspect infrastructure and output optimized settings (parameters)'
    opts.separator ''
    opts.separator 'Options:'
    opts.separator ''
    options[:common] = false
    opts.on('--common', 'Extract common settings from node-specific settings') do
      options[:common] = true
    end
    options[:current] = false
    opts.on('--current', 'Output currently-defined settings (not including defaults)') do
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
      options[:memory_per_jruby] = me
    end
    opts.on('--memory_reserved_for_os MB', 'Amount of RAM to reserve for the operating system') do |mo|
      options[:memory_reserved_for_os] = mo
    end
    opts.on('-h', '--help', 'Display help') do
      puts opts
      puts
      exit 0
    end
  end
  parser.parse!

  Puppet.debug = options[:debug]

  Puppet.debug _("Command Options: %{options}") % { options: options }

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
      Puppet.debug _("Adding %{enterprise_module} to LOAD_PATH: %{enterprise_module_lib}") % { enterprise_module: enterprise_module, enterprise_module_lib: enterprise_module_lib }
      $LOAD_PATH.unshift(enterprise_module_lib)
    end
  end

  require_relative 'tune/calculate'
  require_relative 'tune/configuration'
  require_relative 'tune/inventory'

  Tune = PuppetX::Puppetlabs::Tune.new(options)

  if options[:current]
    Tune.output_current_settings
  else
    Tune.output_optimized_settings
  end
end
