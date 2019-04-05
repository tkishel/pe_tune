#!/opt/puppetlabs/puppet/bin/ruby

# Notes:
#
# This script optimizes the settings documented in tuning_monolithic:
#   https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not optimize the following settings in puppetlabs-puppet_enterprise:
#   puppet_enterprise::profile::database::effective_cache_size
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
        param_names = [
          'puppet_enterprise::master::puppetserver::jruby_max_active_instances',
          'puppet_enterprise::master::puppetserver::reserved_code_cache',
          'puppet_enterprise::profile::amq::broker::heap_mb',
          'puppet_enterprise::profile::console::java_args',
          'puppet_enterprise::profile::database::shared_buffers',
          'puppet_enterprise::profile::database::autovacuum_max_workers',
          'puppet_enterprise::profile::database::autovacuum_work_mem',
          'puppet_enterprise::profile::database::maintenance_work_mem',
          'puppet_enterprise::profile::database::max_connections',
          'puppet_enterprise::profile::database::work_mem',
          'puppet_enterprise::profile::master::java_args',
          'puppet_enterprise::profile::orchestrator::java_args',
          'puppet_enterprise::profile::puppetdb::java_args',
          'puppet_enterprise::puppetdb::command_processing_threads',
        ]
        param_names.delete('puppet_enterprise::profile::amq::broker::heap_mb') if pe_2019_or_newer?
        param_names
      end

      # List of classes used by this module.

      def tunable_class_names
        class_names = [
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
        class_names.delete('amq::broker') if pe_2019_or_newer?
        class_names
      end

      # Initialize this module class.

      def initialize(options)
        if options[:current] && (options[:inventory] || options[:local])
          output_error_and_exit _("The '--current' and '--inventory' or '--local' options are mutually exclusive")
        end

        if options[:estimate] && (options[:inventory] || options[:local])
          output_error_and_exit _("The '--estimate' and '--inventory' or '--local' options are mutually exclusive")
        end

        if options[:inventory] && options[:local]
          output_error_and_exit _("The '--inventory' and '--local' options are mutually exclusive")
        end

        if options[:pe_conf] && !options[:local]
          output_error_and_exit _("The '--pe_conf' option requires the '--local' option")
        end

        # Properties for each node.
        @collected_nodes = {}

        # Settings common to all nodes.
        @collected_settings_common = {}

        # Properties for each node.
        @current_collected_nodes = {}

        # Nodes with classes from Inventory or PuppetDB.
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
        @options[:pe_conf]   = options[:pe_conf]

        @options[:use_current_memory_per_jruby] = options[:use_current_memory_per_jruby]

        # Options specific to the Calculate class.
        calculate_options = {}
        calculate_options[:memory_per_jruby]       = string_to_megabytes(options[:memory_per_jruby])
        calculate_options[:memory_reserved_for_os] = string_to_megabytes(options[:memory_reserved_for_os])

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new(calculate_options)
        @conf = PuppetX::Puppetlabs::Tune::Conf.new('/etc/puppetlabs/enterprise') if @options[:pe_conf]
        @inventory = PuppetX::Puppetlabs::Tune::Inventory.new
        @query = PuppetX::Puppetlabs::Tune::Query.new unless using_inventory?
      end

      # Output current infrastructure.

      def output_infrastructure
        collect_infrastructure_nodes

        output_pe_infrastructure_error_and_exit if unknown_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_external_database?, extra_large?)
      end

      # Output current settings for each infrastructure node.

      def output_current_settings
        current_available_jrubies = collect_current_settings

        @current_collected_nodes.each do |certname, node|
          output_current_settings_for_node(certname, node)
        end

        output_estimated_capacity(current_available_jrubies)
      end

      # Output optimized settings for each infrastructure node.

      def output_optimized_settings
        optimized_available_jrubies = collect_optimized_settings

        collect_optimized_settings_common_to_all_nodes
        @collected_nodes.each do |certname, node|
          output_optimized_settings_for_node(certname, node)
        end
        output_common_settings

        output_estimated_capacity(optimized_available_jrubies)

        output_settings_to_hiera
        output_settings_to_pe_conf
      end

      # Output comparison of currently defined and optimized settings for each infrastructure node.

      def output_compare_current_and_optimized_settings
        collect_current_settings
        collect_optimized_settings

        @current_collected_nodes.each do |certname, current_node|
          optimized_node = @collected_nodes[certname]
          differences = ''
          optimized_node['settings']['params'].each do |param, _value|
            if param.end_with?('::java_args')
              cur = "Xmx: #{current_node['settings']['params'][param]['Xmx']}\tXms: #{current_node['settings']['params'][param]['Xms']}"
              opt = "Xmx: #{optimized_node['settings']['params'][param]['Xmx']}\tXms: #{optimized_node['settings']['params'][param]['Xms']}"
            else
              cur = current_node['settings']['params'][param]
              opt = optimized_node['settings']['params'][param]
            end
            unless cur == opt
              differences << "#{param}\n  defined:\t#{cur}\n  optimized:\t#{opt}\n\n"
            end
          end
          if differences.empty?
            output _('Defined and optimized settings match for %{role} %{certname}') % { role: optimized_node['role'], certname: certname }
          else
            output _('Defined and optimized settings vary for %{role} %{certname}') % { role: optimized_node['role'], certname: certname }
            output_line
            output_data(differences.chomp)
            output _("Rerun this command with and without '--current' for details.")
          end
          output_line
        end
      end

      # Collect current settings for each infrastructure node based upon Classifier and Hiera data.

      def collect_current_settings
        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'Primary Master', settings)
          available_jrubies += available_jrubies_for_node(certname, settings) unless with_compile_masters?
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @nodes_with_role['replica_masters'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'Replica Master', settings)
        end

        # Console Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['console_hosts'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'Console Host', settings)
        end

        # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['puppetdb_hosts'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'PuppetDB Host', settings)
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['database_hosts'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'External Database Host', settings)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['compile_masters'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'Compile Master', settings)
          available_jrubies += available_jrubies_for_node(certname, settings)
        end

        available_jrubies
      end

      # Collect optimized settings for each infrastructure node based upon each node's set of services.

      def collect_optimized_settings
        available_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          node = configuration_for_node(certname)
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_optimized_node(certname, 'Primary Master', node)
          available_jrubies += available_jrubies_for_node(certname, node['settings']) unless with_compile_masters?
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @nodes_with_role['replica_masters'].each do |certname|
          node = configuration_for_node(certname)
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_optimized_node(certname, 'Replica Master', node)
        end

        # Console Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['console_hosts'].each do |certname|
          node = configuration_for_node(certname)
          node['settings'] = @calculator::calculate_console_settings(node)
          collect_optimized_node(certname, 'Console Host', node)
        end

        # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['puppetdb_hosts'].each do |certname|
          node = configuration_for_node(certname)
          node['settings'] = @calculator::calculate_puppetdb_settings(node)
          collect_optimized_node(certname, 'PuppetDB Host', node)
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['database_hosts'].each do |certname|
          node = configuration_for_node(certname)
          node['settings'] = @calculator::calculate_database_settings(node)
          collect_optimized_node(certname, 'External Database Host', node)
        end

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['compile_masters'].each do |certname|
          node = configuration_for_node(certname)
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          collect_optimized_node(certname, 'Compile Master', node)
          available_jrubies += available_jrubies_for_node(certname, node['settings'])
        end

        available_jrubies
      end

      # Return configuration for a node.

      def configuration_for_node(certname)
        node = {}
        resources = resources_for_node(certname)
        output_minimum_system_requirements_error_and_exit(certname) unless meets_minimum_system_requirements?(resources)
        node['certname'] = certname,
        node['classes'] = tunable_classes_for_node(certname)
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

      # Collect node for output.

      def collect_current_node(certname, role, settings)
        properties = {
          'role'      => role,
          'settings'  => settings,
        }
        @current_collected_nodes[certname] = properties
      end

      # Collect node for output to <certname>.yaml.

      def collect_optimized_node(certname, role, node)
        output_minimum_system_requirements_error_and_exit(certname) if node['settings'].empty?
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

      #
      # Interfaces to PuppetX::Puppetlabs::Tune classes.
      #

      # Interface to ::Inventory and ::Query classes.

      def collect_infrastructure_nodes
        if using_inventory?
          @inventory::read_inventory_from_local_system if @options[:local]
          @inventory::read_inventory_from_inventory_file(@options[:inventory]) if @options[:inventory]
          output_error_and_exit _('Unable to read inventory') if @inventory::nodes.empty? || @inventory::roles.empty?
          @inventory::convert_inventory_roles_to_classes
          output_error_and_exit _('Unable to read inventory') if @inventory::classes.empty? || @inventory::classes == @inventory::default_inventory_classes
        else
          @query::pe_environment(Puppet['certname'])
        end

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
      end

      # Interface to ::Inventory and ::Query classes.

      def collect_nodes_with_class(classname)
        if using_inventory?
          Puppet.debug('Using Inventory for collect_nodes_with_class')
          # Key names are downcased in Inventory.
          class_name_in_inventory = classname.downcase
          @nodes_with_class[classname] = @inventory::classes[class_name_in_inventory].to_a
        else
          Puppet.debug('Using PuppetDB for collect_nodes_with_class')
          # Key names are capitalized in PuppetDB.
          class_name_in_puppetdb = classname.split('::').map(&:capitalize).join('::')
          @nodes_with_class[classname] = @query::infra_nodes_with_class(class_name_in_puppetdb)
          output_error_and_exit _('Unable to connect to PuppetDB to query classes') if @nodes_with_class[classname].nil?
        end
      end

      # Interface to ::Inventory and ::Query classes.
      # Override when testing with environment variables.

      def resources_for_node(certname)
        resources = {}
        if using_inventory?
          Puppet.debug('Using Inventory for resources_for_node')
          output_error_and_exit _("Cannot read node: %{certname}") % { certname: certname } unless @inventory::nodes[certname] && @inventory::nodes[certname]['resources']
          node_facts = @inventory::nodes[certname]['resources']
          output_error_and_exit _("Cannot read resources for node: %{certname}") % { certname: certname } unless node_facts['cpu'] && node_facts['ram']
          resources['cpu'] = node_facts['cpu'].to_i
          resources['ram'] = string_to_bytes(node_facts['ram']).to_i
        else
          Puppet.debug('Using PuppetDB for resources_for_node')
          node_facts = @query::node_facts(certname)
          output_error_and_exit _('Unable to connect to PuppetDB to query facts') if node_facts.nil?
          output_error_and_exit _("Cannot query resources for node: %{certname}") % { certname: certname } unless node_facts['processors'] && node_facts['memory']
          resources['cpu'] = node_facts['processors']['count'].to_i
          resources['ram'] = node_facts['memory']['system']['total_bytes'].to_i
        end
        resources['ram'] = (resources['ram'] / 1024 / 1024).to_i
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

      # Interface to ::Query class.

      def current_settings_for_node(certname, setting_names)
        result = @query::hiera_classifier_settings(certname, setting_names)
        output_error_and_exit _('Unable to connect to PuppetDB to query current node settings') if result.nil?
        result
      end

      def active_node_count
        result = @query::active_node_count
        output_error_and_exit _('Unable to connect to PuppetDB to query active nodes') if result.nil?
        result
      end

      def average_compile_time(report_limit)
        result = @query::average_compile_time(report_limit)
        output_error_and_exit _('Unable to connect to PuppetDB to query average compile time') if result.nil?
        result
      end

      #
      # Output
      #

      # Output Hiera YAML files.

      def output_settings_to_hiera
        return unless @options[:hiera]
        hiera_directory = @options[:hiera]
        hiera_subdirectory = "#{hiera_directory}/nodes"
        return if File.directory?(hiera_directory) && File.directory?(hiera_subdirectory)
        Dir.mkdir(hiera_directory) unless File.directory?(hiera_directory)
        output_error_and_exit _("Unable to create output directory: %{directory}") % { directory: hiera_directory } unless File.directory?(hiera_directory)
        Dir.mkdir(hiera_subdirectory) unless File.directory?(hiera_subdirectory)
        output_error_and_exit _("Unable to create output directory: %{directory}") % { directory: hiera_subdirectory } unless File.directory?(hiera_subdirectory)
        @collected_nodes.each do |certname, properties|
          next if properties['settings']['params'].empty?
          output_file = "#{@options[:hiera]}/nodes/#{certname}.yaml"
          File.write(output_file, properties['settings']['params'].to_yaml)
          output _("Wrote Hiera YAML file: %{output_file}") % { output_file: output_file }
          output_line
        end
        return if @collected_settings_common.empty?
        output_file = "#{@options[:hiera]}/common.yaml"
        File.write(output_file, @collected_settings_common.to_yaml)
      end

      # Output HOCON to pe.conf.

      def output_settings_to_pe_conf
        return unless @options[:pe_conf] && @options[:local]
        output_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
        @collected_nodes.each do |_certname, properties|
          next if properties['settings']['params'].empty?
          if @conf::write(properties['settings']['params'])
            output _("Merged optimized settings to: %{output_file}") % { output_file: output_file }
          else
            output _("Unable to output settings to: %{output_file} ... existing settings found.") % { output_file: output_file }
          end
          output_line
        end
      end

      # Consolidate output.

      def output(info)
        puts "# #{info}"
      end

      def output_line
        puts "\n"
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
        output _("Puppet Infrastructure Summary: Found a %{type} Infrastructure%{w_cm}%{w_ep}%{w_xl}") % { type: type, w_cm: w_cm, w_ep: w_ep, w_xl: w_xl }
        output_line
      end

      # Output current information for a node.

      def output_current_settings_for_node(certname, node)
        if node['settings']['params'].empty?
          output _("Found default settings for %{role} %{certname}") % { role: node['role'], certname: certname }
        else
          output _("Found defined settings for %{role} %{certname}") % { role: node['role'], certname: certname }
          output_line
          output_data(JSON.pretty_generate(node['settings']['params']))
          # output_data(node['settings']['params'].to_yaml)
        end
        output_line
        unless node['settings']['duplicates'].count.zero?
          output _('Found duplicate defined settings in Hiera and in the Classifier (Console):')
          output_line
          output_data(node['settings']['duplicates'].join("\n"))
          output_line
          output _('Define settings in Hiera (preferred) or the Classifier, but not both.')
          output _('Note that Hiera includes settings defined in pe.conf.')
        end
      end

      # Output optimized information for a node.

      def output_optimized_settings_for_node(certname, node)
        output _("Found %{cpu} CPU(s) / %{ram} MB RAM for %{role} %{certname}") % { cpu: node['resources']['cpu'], ram: node['resources']['ram'], role: node['role'], certname: certname }
        unless node['settings']['params'].empty?
          output _("Specify the following optimized settings in Hiera in nodes/%{certname}.yaml") % { certname: certname }
          output_line
          # output_data(JSON.pretty_generate(node['settings']['params']))
          output_data(node['settings']['params'].to_yaml)
        end
        unless node['settings']['totals'].empty?
          if node['settings']['totals']['CPU']
            total = node['settings']['totals']['CPU']['total']
            used = node['settings']['totals']['CPU']['used']
            free = total - used
            output _("CPU Summary: Total/Used/Free: %{total}/%{used}/%{free} for %{certname}") % { total: total, used: used, free: free, certname: certname }
          end
          if node['settings']['totals']['RAM']
            total = node['settings']['totals']['RAM']['total']
            used = node['settings']['totals']['RAM']['used']
            free = total - used
            output _("RAM Summary: Total/Used/Free: %{total}/%{used}/%{free} for %{certname}") % { total: total, used: used, free: free, certname: certname }
          end
          if node['settings']['totals']['MB_PER_JRUBY']
            mb_per_puppetserver_jruby = node['settings']['totals']['MB_PER_JRUBY']
            output _("JVM Summary: Using %{mb_per_puppetserver_jruby} MB per Puppet Server JRuby for %{certname}") % { mb_per_puppetserver_jruby: mb_per_puppetserver_jruby, certname: certname }
          end
        end
        output_line
      end

      def output_common_settings
        return unless @options[:common]
        return if @collected_settings_common.empty?
        output _('Specify the following optimized settings in Hiera in common.yaml')
        output_line
        output(@collected_settings_common.to_yaml)
        output_line
      end

      def output_estimated_capacity(available_jrubies)
        return unless @options[:estimate]
        run_interval = Puppet[:runinterval]
        active_nodes = active_node_count
        report_limit = @calculator::calculate_run_sample(active_nodes, run_interval)
        average_compile_time = average_compile_time(report_limit)
        maximum_nodes = @calculator::calculate_maximum_nodes(average_compile_time, available_jrubies, run_interval)
        minimum_jrubies = @calculator::calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
        output _('Puppet Infrastructure Estimated Capacity')
        output_line
        output _("Found %{available_jrubies} available JRubies and %{active_nodes} active nodes.") % { available_jrubies: available_jrubies, active_nodes: active_nodes }
        output _("Found a run interval of %{run_interval} seconds and an average compile time of %{average_compile_time} seconds.") % { run_interval: run_interval, average_compile_time: average_compile_time }
        output _("A maximum of %{maximum_nodes} nodes can be served by %{available_jrubies} JRubies.") % { maximum_nodes: maximum_nodes, available_jrubies: available_jrubies }
        output _("A minimum of %{minimum_jrubies} JRubies are required to serve %{active_nodes} nodes.") % { minimum_jrubies: minimum_jrubies, active_nodes: active_nodes }
        output _('Note that available JRubies does not include the Primary Master when using Compile Masters.') if with_compile_masters?
        output_line
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

      def tunable_classes_for_node(certname)
        classes = {}
        tunable_class_names.each do |classname|
          classes[classname] = node_with_class?(certname, classname)
        end
        classes
      end

      # Identify JRuby version on a node.
      # puppetserver::jruby_9k_enabled is a setting added to PE 2018.
      # puppetserver::jruby_jar is a setting added to PE 2017 and is outside the scope of this code.

      def with_jruby9k_enabled?(certname)
        # Return the default based upon version, when using Inventory.
        return pe_2018_or_newer? if using_inventory?
        # Does the jruby-9k.jar file exist?
        jr9kjar = '/opt/puppetlabs/server/apps/puppetserver/jruby-9k.jar'
        return false unless File.exist?(jr9kjar)
        # Does the jruby_9k_enabled setting exist?
        jruby_9k_enabled = 'puppet_enterprise::master::puppetserver::jruby_9k_enabled'
        settings = current_settings_for_node(certname, [jruby_9k_enabled])
        # The setting does not exist, return the default based upon version.
        return pe_2018_or_newer? unless settings['params'].key?(jruby_9k_enabled)
        # Does the jruby_9k_enabled setting equal true?
        settings['params'][jruby_9k_enabled] == 'true'
      end

      # Identify available JRubies on a node.

      def available_jrubies_for_node(certname, settings)
        default_jrubies = [resources_for_node(certname)['cpu'] - 1, 4].min
        settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || default_jrubies
      end

      # Identify current memory_per_jruby on a node.

      def current_memory_per_jruby_for_node(certname)
        return 0 if @options[:local]
        return 0 unless @options[:use_current_memory_per_jruby]
        settings = current_settings_for_node(certname, tunable_param_names)
        return 0 unless settings['params']
        return 0 unless settings['params']['puppet_enterprise::profile::master::java_args']
        return 0 unless settings['params']['puppet_enterprise::profile::master::java_args']['Xmx']
        return 0 unless settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
        jxmx = settings['params']['puppet_enterprise::profile::master::java_args']['Xmx']
        jmai = settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
        return 0 unless jxmx && jmai
        (string_to_megabytes(jxmx) / jmai).to_i
      end

      #
      # Utilities
      #

      # Do not query PuppetDB when using Inventory.

      def using_inventory?
        @options[:local] || @options[:inventory]
      end

      # Verify minimum system requirements.

      def meets_minimum_system_requirements?(resources)
        return true if @options[:force]
        # Round down (8192 -> 7680) to mirror fit_to_memory_percentage in calculate.rb.
        resources['cpu'] >= 4 && resources['ram'] >= 7680
      end

      # Versions
      # Allows mergeups from PE 2018 LTS to STS. Revisit after PE 2018 is EOL.

      def pe_2018_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('5.5.0')
      end

      def pe_2019_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')
      end

      # Convert (for example) 16, 16g, 16384m, 16777216k, or 17179869184b to 17179869184.

      def string_to_bytes(s, default_units = 'g')
        return 0 if s.nil?
        matches = %r{(\d+)\s*(\w?)}.match(s.to_s)
        output_error_and_exit _("Unable to convert %{s} to bytes") % { s: s } if matches.nil?
        value = matches[1].to_f
        units = matches[2].empty? ? default_units : matches[2].downcase
        case units
        when 'b' then return value.to_i
        when 'k' then return (value * (1 << 10)).to_i
        when 'm' then return (value * (1 << 20)).to_i
        when 'g' then return (value * (1 << 30)).to_i
        else
          output_error_and_exit _("Unable to convert %{s} to bytes, valid units are: b, k, m, g") % { s: s }
        end
      end

      # Convert (for example) 1g, 1024, 1024m to 1024.

      def string_to_megabytes(s, default_units = 'm')
        return 0 if s.nil?
        matches = %r{(\d+)\s*(\w?)}.match(s.to_s)
        output_error_and_exit _("Unable to convert %{s} to megabytes") % { s: s } if matches.nil?
        value = matches[1].to_f
        units = matches[2].empty? ? default_units : matches[2].downcase
        case units
        when 'm' then return value.to_i
        when 'g' then return (value * (1 << 10)).to_i
        else
          output_error_and_exit _("Unable to convert %{s} to megabytes, valid units are: m, g") % { s: s }
        end
      end
    end
  end
end

# The following code allows this class to be executed as a standalone script.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require_relative 'tune/cli'
else
  require 'puppet_x/puppetlabs/tune/calculate'
  require 'puppet_x/puppetlabs/tune/conf'
  require 'puppet_x/puppetlabs/tune/inventory'
  require 'puppet_x/puppetlabs/tune/query'
end
