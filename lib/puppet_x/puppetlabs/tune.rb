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
#   export TEST_CPU=2; export TEST_RAM=6144;
# These are necessary to accomodate manual testing and pe_acceptance_tests/acceptance/tests/faces/infrastructure/tune.rb.

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current, or calculate optimized settings.
    class Tune
      # List of class parameters (settings) managed by this command.
      def tunable_param_names
        param_names = [
          'puppet_enterprise::master::puppetserver::jruby_max_active_instances',
          'puppet_enterprise::master::puppetserver::reserved_code_cache',
          'puppet_enterprise::profile::amq::broker::heap_mb',
          'puppet_enterprise::profile::console::java_args',
          'puppet_enterprise::profile::database::shared_buffers',
          'puppet_enterprise::profile::master::java_args',
          'puppet_enterprise::profile::orchestrator::java_args',
          'puppet_enterprise::profile::orchestrator::jruby_max_active_instances',
          # 'puppet_enterprise::profile::orchestrator::reserved_code_cache',
          'puppet_enterprise::profile::puppetdb::java_args',
          'puppet_enterprise::puppetdb::command_processing_threads',
        ]
        param_names.delete('puppet_enterprise::profile::amq::broker::heap_mb') if pe_2019_or_newer?
        # ORCH-2384
        unless pe_2019_2_or_newer?
          param_names.delete('puppet_enterprise::profile::orchestrator::jruby_max_active_instances')
          # param_names.delete('puppet_enterprise::profile::orchestrator::reserved_code_cache')
        end
        param_names
      end

      # List of classes queried by this command.

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

      # Initialize tuning: command options, class variables, and objects.

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

        if options[:use_current_memory_per_jruby] && options[:memory_per_jruby]
          output_error_and_exit _("The '--use_current_memory_per_jruby' and '--memory_per_jruby' options are mutually exclusive")
        end

        # Optimized properties for each PE Infrastructure node found in Inventory or PuppetDB.
        @collected_nodes = {}

        # Current properties for each PE Infrastructure node found in Inventory or PuppetDB.
        @current_collected_nodes = {}

        # Settings common to all PE Infrastructure nodes, for use in common.yaml.
        @collected_settings_common = {}

        # Nodes with each tunable PE Infrastructure class.
        @nodes_with_class = {}

        # Nodes with each PE Infrastructure role (Master, Compiler, etc.).
        @nodes_with_role = {}

        # Options specific to this Tune class.
        @options = {}
        @options[:common]    = options[:common]
        @options[:estimate]  = options[:estimate]
        @options[:force]     = options[:force]
        @options[:hiera]     = options[:hiera]
        @options[:inventory] = options[:inventory]
        @options[:local]     = options[:local]
        @options[:node]      = options[:node]
        @options[:pe_conf]   = options[:pe_conf]

        # Internal option. Shh!
        @options[:quiet]     = (@options[:hiera] || @options[:pe_conf])

        @options[:use_current_memory_per_jruby] = options[:use_current_memory_per_jruby]

        # Options specific to the Calculate class.
        calculate_options = {}
        calculate_options[:memory_per_jruby]       = string_to_megabytes(options[:memory_per_jruby])
        calculate_options[:memory_reserved_for_os] = string_to_megabytes(options[:memory_reserved_for_os])

        @calculator = PuppetX::Puppetlabs::Tune::Calculate.new(calculate_options)
        @pe_conf = PuppetX::Puppetlabs::Tune::PEConf.new('/etc/puppetlabs/enterprise') if @options[:pe_conf]
        @inventory = PuppetX::Puppetlabs::Tune::Inventory.new
        @query = PuppetX::Puppetlabs::Tune::Query.new unless using_inventory?
      end

      # Output the current infrastructure summary.

      def output_infrastructure
        output_pe_infrastructure_error_and_exit if unknown_infrastructure?
        output_pe_infrastucture_summary(monolithic?, with_compile_masters?, with_compilers?, with_external_database?)
      end

      # Output the current settings for each PE Infrastructure node.

      def output_current_settings
        current_total_puppetserver_jrubies = collect_current_settings

        @current_collected_nodes.sort_by { |_k, node| [node['order'], node['certname']] }.each do |certname, node|
          next if @options[:node] && certname != @options[:node]
          output_current_settings_for_node(certname, node)
        end

        output_estimated_capacity(current_total_puppetserver_jrubies)
        output_compilers_autotune
      end

      # Output optimized settings for each PE Infrastructure node.

      def output_optimized_settings
        optimized_total_puppetserver_jrubies = collect_optimized_settings

        collect_optimized_settings_common_to_all_nodes
        @collected_nodes.sort_by { |_k, node| [node['order'], node['certname']] }.each do |certname, node|
          next if @options[:node] && certname != @options[:node]
          output_optimized_settings_for_node(certname, node)
        end
        output_common_settings

        output_estimated_capacity(optimized_total_puppetserver_jrubies)
        output_compilers_autotune

        output_settings_to_hiera
        output_settings_to_pe_conf
      end

      # Output a comparison of current and optimized settings for each PE Infrastructure node.

      def output_compare_current_and_optimized_settings
        collect_current_settings
        collect_optimized_settings

        @current_collected_nodes.sort_by { |_k, node| [node['order'], node['certname']] }.each do |certname, current_node|
          next if @options[:node] && certname != @options[:node]
          if current_node['settings']['params'].empty?
            output _('No currently defined settings to compare for %{role} %{certname}') % { role: current_node['role'], certname: certname }
            next
          end
          optimized_node = @collected_nodes[certname]
          next unless optimized_node
          differences = ''
          optimized_node['settings']['params'].each do |param, _value|
            if param.end_with?('::java_args')
              cur = current_node['settings']['params'].key?(param) ? "Xmx: #{current_node['settings']['params'][param]['Xmx']}\tXms: #{current_node['settings']['params'][param]['Xms']}" : "Xmx: \t\tXms: "
              opt = "Xmx: #{optimized_node['settings']['params'][param]['Xmx']}\tXms: #{optimized_node['settings']['params'][param]['Xms']}"
            else
              cur = current_node['settings']['params'].key?(param) ? current_node['settings']['params'][param] : ''
              opt = optimized_node['settings']['params'][param]
            end
            unless cur == opt
              differences << "#{param}\n  current:\t#{cur}\n  optimized:\t#{opt}\n\n"
            end
          end
          if differences.empty?
            output _('Currently defined and optimized settings match for %{role} %{certname}') % { role: optimized_node['role'], certname: certname }
          else
            output _('Currently defined and optimized settings vary for %{role} %{certname}') % { role: optimized_node['role'], certname: certname }
            output_line
            output_data(differences.chomp)
          end
          output_line
        end
      end

      # Collect current settings for each PE Infrastructure node from Classifier and Hiera data.
      # Based upon each node's set of services (aka PE Infrastructure role).

      def collect_current_settings
        total_puppetserver_jrubies = 0

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          settings = current_settings_for_node(certname, tunable_param_names)
          collect_current_node(certname, 'Primary Master', settings)
          total_puppetserver_jrubies += total_puppetserver_jrubies_for_node(certname, settings) unless with_compile_masters?
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
          total_puppetserver_jrubies += total_puppetserver_jrubies_for_node(certname, settings)
        end

        # Return the total of all jrubies, for use when estimating capacity.
        total_puppetserver_jrubies
      end

      # Collect optimized settings for each PE Infrastructure node.
      # Based upon each node's set of services (aka PE Infrastructure role).

      def collect_optimized_settings
        total_puppetserver_jrubies = 0
        total_puppetdb_connections = 0

        # Compile Masters: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['compile_masters'].each do |certname|
          node = configuration_for_node(certname)
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          if compiler?(node)
            output_autotune(node)
            next
          end
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'Compile Master', node)
          total_puppetserver_jrubies += total_puppetserver_jrubies_for_node(certname, node['settings'])
          total_puppetdb_connections += total_puppetdb_connections_for_node(certname, node['settings'])
        end

        # Primary Master: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['primary_masters'].each do |certname|
          node = configuration_for_node(certname)
          node['infrastructure']['compiler_connections'] = total_puppetdb_connections
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'Primary Master', node)
          total_puppetserver_jrubies += total_puppetserver_jrubies_for_node(certname, node['settings']) unless with_compile_masters?
        end

        # Replica Master: Applicable to Monolithic Infrastructures.
        @nodes_with_role['replica_masters'].each do |certname|
          node = configuration_for_node(certname)
          node['infrastructure']['compiler_connections'] = total_puppetdb_connections
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          node['current_memory_per_jruby'] = current_memory_per_jruby_for_node(certname)
          node['settings'] = @calculator::calculate_master_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'Replica Master', node)
        end

        # Console Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['console_hosts'].each do |certname|
          node = configuration_for_node(certname)
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          node['settings'] = @calculator::calculate_console_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'Console Host', node)
        end

        # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.
        @nodes_with_role['puppetdb_hosts'].each do |certname|
          node = configuration_for_node(certname)
          node['infrastructure']['compiler_connections'] = total_puppetdb_connections
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          node['settings'] = @calculator::calculate_puppetdb_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'PuppetDB Host', node)
        end

        # External Database Host: Applicable to Monolithic and Split Infrastructures.
        @nodes_with_role['database_hosts'].each do |certname|
          node = configuration_for_node(certname)
          node['infrastructure']['compiler_connections'] = total_puppetdb_connections
          unless meets_minimum_system_requirements?(node['resources'])
            output_minimum_system_requirements_warning(node)
            next
          end
          node['settings'] = @calculator::calculate_database_settings(node)
          if node['settings'].nil? || node['settings'].empty?
            output_calculation_warning(node)
            next
          end
          collect_optimized_node(certname, 'External Database Host', node)
        end

        # Return the total of all jrubies, for use when estimating capacity.
        total_puppetserver_jrubies
      end

      # Configuration for a PE Infrastructure node, used to calculate its settings.

      def configuration_for_node(certname)
        node = {}
        resources = resources_for_node(certname)
        node['certname'] = certname
        node['classes'] = tunable_classes_for_node(certname)
        node['infrastructure'] = {
          'is_monolithic'        => monolithic?,
          'with_compile_masters' => with_compile_masters?,
        }
        node['resources'] = resources
        node['type'] = {
          'is_monolithic_master'    => monolithic_master?(certname),
          'is_replica_master'       => replica_master?(certname),
          'is_compile_master'       => compile_master?(certname),
          'with_jruby9k_enabled'    => with_jruby9k_enabled?(certname),
          'with_orchestrator_jruby' => pe_2019_2_or_newer?,
        }
        node
      end

      # Collect the current settings for a PE Infrastructure node into a structure for output.

      def collect_current_node(certname, role, settings)
        properties = {
          'certname' => certname,
          'order'    => output_order(role),
          'role'     => role,
          'settings' => settings,
        }
        @current_collected_nodes[certname] = properties
      end

      # Collect the optimized settings for a PE Infrastructure node into a structure for output.

      def collect_optimized_node(certname, role, node)
        properties = {
          'certname'  => certname,
          'order'     => output_order(role),
          'resources' => node['resources'],
          'role'      => role,
          'settings'  => node['settings'],
        }
        @collected_nodes[certname] = properties
      end

      # Establish an intuitive output (singletons, multiples) order of hosts.

      def output_order(role)
        case role
        when 'Primary Master'
          1
        when 'Replica Master'
          2
        when 'Console Host'
          3
        when 'PuppetDB Host'
          4
        when 'External Database Host'
          5
        else
          9
        end
      end

      # Extract optimized settings common to all PE Infrastructure nodes.

      def collect_optimized_settings_common_to_all_nodes
        return unless @options[:common]
        nodes_with_param = {}
        @collected_nodes.each do |certname, properties|
          next if @options[:node] && certname != @options[:node]
          properties['settings']['params'].each do |param_name, param_value|
            nodes_with_param[param_name] = {} unless nodes_with_param.key?(param_name)
            nodes_with_param[param_name][certname] = param_value
          end
        end
        nodes_with_param.each do |param_name, nodes|
          next unless nodes.values.uniq.length == 1
          @collected_settings_common[param_name] = nodes.values[0]
          nodes.each do |certname, _value|
            next if @options[:node] && certname != @options[:node]
            @collected_nodes[certname]['settings']['params'].delete(param_name)
          end
        end
      end

      #
      # Interfaces to PuppetX::Puppetlabs::Tune classes.
      #

      # Interface to ::Inventory and ::Query classes.
      # Identify PE Infrastructure nodes by role, based upon the PE classes declared on the node.

      def collect_infrastructure_nodes
        if using_inventory?
          # The 'local' option is limited to use with a Monolithic Master during a clean install when there is no PuppetDB to query.
          @inventory::read_inventory_from_local_system if @options[:local]
          @inventory::read_inventory_from_inventory_file(@options[:inventory]) if @options[:inventory]
          output_error_and_exit _("Unable to parse 'nodes' or 'roles' from inventory") if @inventory::nodes.empty? || @inventory::roles.empty?
          @inventory::convert_inventory_roles_to_classes
          output_error_and_exit _("Unable to parse 'classes' from inventory") if @inventory::classes.empty? || @inventory::classes == @inventory::default_inventory_classes
        else
          @query::pe_environment(Puppet['certname'])
          output_error_and_exit _("Unable to parse the 'environment' of this PE Infrastructure") if @query::environment.empty?
          output_error_and_exit _("Unable to parse the 'environmentpath' of this PE Infrastructure") if @query::environmentpath.empty?
        end

        tunable_class_names.each do |classname|
          collect_nodes_with_class(classname)
        end

        # Mappings vary between PE Infrastructure roles, profiles, and classes.
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

      # Identify the nodes with a specific PE Infrastructure class.

      def collect_nodes_with_class(classname)
        if using_inventory?
          Puppet.debug('Using Inventory for collect_nodes_with_class()')
          # Key names are downcased in Inventory.
          class_name_in_inventory = classname.downcase
          @nodes_with_class[classname] = @inventory::classes[class_name_in_inventory].to_a
        else
          Puppet.debug('Using PuppetDB for collect_nodes_with_class()')
          # Key names are capitalized in PuppetDB.
          class_name_in_puppetdb = classname.split('::').map(&:capitalize).join('::')
          @nodes_with_class[classname] = @query::infra_nodes_with_class(class_name_in_puppetdb)
          output_error_and_exit _('Unable to connect to PuppetDB to query infra_nodes_with_class()') if @nodes_with_class[classname].nil?
        end
      end

      # Identify the system resources for a specific PE Infrastructure node.
      # Override when testing with environment variables.

      def resources_for_node(certname)
        resources = {}
        if using_inventory?
          Puppet.debug('Using Inventory for resources_for_node()')
          output_error_and_exit _("Unable to parse inventory for node: %{certname}") % { certname: certname } unless @inventory::nodes[certname] && @inventory::nodes[certname]['resources']
          node_facts = @inventory::nodes[certname]['resources']
          output_error_and_exit _("Unable to parse inventory for node: %{certname}") % { certname: certname } unless node_facts['cpu'] && node_facts['ram']
          resources['cpu'] = node_facts['cpu'].to_i
          resources['ram'] = string_to_bytes(node_facts['ram']).to_i
          resources['pp_auth_role'] = ''
        else
          Puppet.debug('Using PuppetDB for resources_for_node()')
          node_facts = @query::node_facts(certname)
          # if node_facts.nil?
          #   Puppet.debug('Unable to use PuppetDB')
          #   Puppet.debug('Using puppetserver/yaml/facts for resources_for_node()')
          #   node_facts = node_facts_from_yaml_facts(certname)
          #   Puppet.debug('Unable to use puppetserver/yaml/facts') if node_facts.nil?
          # end
          output_error_and_exit _('Unable to connect to PuppetDB to query node_facts()') if node_facts.nil?
          output_error_and_exit _("Cannot query resources for node: %{certname}") % { certname: certname } unless node_facts['processors'] && node_facts['memory']
          resources['cpu'] = node_facts['processors']['count'].to_i
          resources['ram'] = node_facts['memory']['system']['total_bytes'].to_i
          # Trusted facts are not really resources, but this is where we query PuppetDB for facts.
          if node_facts['trusted'] && node_facts['trusted']['extensions'] && node_facts['trusted']['extensions']['pp_auth_role']
            resources['pp_auth_role'] = node_facts['trusted']['extensions']['pp_auth_role']
          else
            resources['pp_auth_role'] = ''
          end
        end
        resources['ram'] = (resources['ram'] / 1024 / 1024).to_i
        if ENV['TEST_CPU']
          Puppet.debug("Using ENV['TEST_CPU'] = #{ENV['TEST_CPU']} for #{certname}")
          resources['cpu'] = ENV['TEST_CPU'].to_i
        end
        if ENV['TEST_RAM']
          Puppet.debug("Using ENV['TEST_RAM' = #{ENV['TEST_RAM']} for #{certname}")
          resources['ram'] = ENV['TEST_RAM'].to_i
        end
        Puppet.debug("Using CPU = #{resources['cpu']} and RAM = #{resources['ram']} for #{certname}")
        resources
      end

      # Fall back to reading facts on disk.

      def node_facts_from_yaml_facts(certname)
        yaml_file = "/opt/puppetlabs/server/data/puppetserver/yaml/facts/#{certname}.yaml"
        return unless File.file?(yaml_file)
        yaml_facts = YAML.load_file(yaml_file)
        yaml_facts.values
      end

      # Interface to ::Query class.

      # Identify the current settings for a specific PE Infrastructure node.

      def current_settings_for_node(certname, setting_names)
        result = @query::hiera_classifier_settings(certname, setting_names)
        output_error_and_exit _('Unable to connect to PuppetDB to query current_settings_for_node()') if result.nil?
        result
      end

      # Query PuppetDB.

      def active_node_count
        result = @query::active_node_count
        output_error_and_exit _('Unable to connect to PuppetDB to query active_node_count()') if result.nil?
        result
      end

      # Query PuppetDB.

      def average_compile_time(report_limit)
        result = @query::average_compile_time(report_limit)
        output_error_and_exit _('Unable to connect to PuppetDB to query average_compile_time()') if result.nil?
        result
      end

      #
      # Output
      #

      # Output optimized settings to a directory of Hiera YAML files.

      def output_settings_to_hiera
        return unless @options[:hiera]
        hiera_directory = @options[:hiera]
        hiera_subdirectory = "#{hiera_directory}/nodes"
        Dir.mkdir(hiera_directory) unless File.directory?(hiera_directory)
        output_error_and_exit _("Unable to create output directory: %{directory}") % { directory: hiera_directory } unless File.directory?(hiera_directory)
        Dir.mkdir(hiera_subdirectory) unless File.directory?(hiera_subdirectory)
        output_error_and_exit _("Unable to create output subdirectory: %{directory}") % { directory: hiera_subdirectory } unless File.directory?(hiera_subdirectory)
        @collected_nodes.sort_by { |_k, node| [node['order'], node['certname']] }.each do |certname, properties|
          next if @options[:node] && certname != @options[:node]
          next if properties['settings']['params'].empty?
          output_file = "#{@options[:hiera]}/nodes/#{certname}.yaml"
          if ENV['SORT_KEYS']
            File.write(output_file, properties['settings']['params'].sort.to_h.to_yaml)
          else
            File.write(output_file, properties['settings']['params'].to_yaml)
          end
          output _("Wrote Hiera YAML file: %{output_file}") % { output_file: output_file }
          output_line
        end
        return if @collected_settings_common.empty?
        output_file = "#{@options[:hiera]}/common.yaml"
        File.write(output_file, @collected_settings_common.to_yaml)
      end

      # Output optimized settings to pe.conf.

      def output_settings_to_pe_conf
        return unless @options[:pe_conf]
        @collected_nodes.sort_by { |_k, node| [node['order'], node['certname']] }.each do |_certname, properties|
          next if @options[:node] && certname != @options[:node]
          next if properties['settings']['params'].empty?
          if @pe_conf::write(properties['settings']['params'])
            output _("Merged optimized settings to: %{output_file}") % { output_file: @pe_conf::file }
          else
            output _("Unable to output optimized settings to: %{output_file}: conflicting settings found.") % { output_file: @pe_conf::file }
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

      # Output highlighted output, from 'puppet/util/colors'.

      def output_data(info)
        puts "\e[0;32m#{info}\e[0m"
      end

      def output_warning(info)
        puts "\e[0;33m#{info}\e[0m"
      end

      # Output a summary of PE Infrastucture information.

      def output_pe_infrastucture_summary(is_monolithic, with_compile_masters, with_compilers, with_external_database)
        return if @options[:quiet]
        type = is_monolithic ? 'Monolithic' : 'Split'
        w_cm = with_compile_masters   ? ' with Compile Masters' : ''
        w_cm = with_compilers         ? ' with Compilers' : w_cm
        w_ed = with_external_database ? ' with an External Database' : ''
        output _("Puppet Infrastructure Summary: Found a %{type} Infrastructure%{w_cm}%{w_ed}") % { type: type, w_cm: w_cm, w_ed: w_ed }
        output_line
      end

      # Output currently defined settings for a PE Infrastucture node.

      def output_current_settings_for_node(certname, node)
        return if @options[:quiet]
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

      # Output system resources and optimized settings for a PE Infrastucture node.

      def output_optimized_settings_for_node(certname, node)
        return if @options[:quiet]
        output _("Found %{cpu} CPU(s) / %{ram} MB RAM for %{role} %{certname}") % { cpu: node['resources']['cpu'], ram: node['resources']['ram'], role: node['role'], certname: certname }
        unless node['settings']['params'].empty?
          output _("Specify the following optimized settings in Hiera in nodes/%{certname}.yaml") % { certname: certname }
          output_line
          # output_data(JSON.pretty_generate(node['settings']['params']))
          if ENV['SORT_KEYS']
            output_data(node['settings']['params'].sort.to_h.to_yaml)
          else
            output_data(node['settings']['params'].to_yaml)
          end
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

      # Output optimized settings common to all PE Infrastucture nodes.

      def output_common_settings
        return if @options[:quiet]
        return unless @options[:common]
        return if @collected_settings_common.empty?
        output _('Specify the following optimized settings in Hiera in common.yaml')
        output_line
        if ENV['SORT_KEYS']
          output_data(@collected_settings_common.sort.to_h.to_yaml)
        else
          output_data(@collected_settings_common.to_yaml)
        end
        output_line
      end

      # Output an estimated capacity summary for this PE Infrastucture.

      def output_estimated_capacity(total_puppetserver_jrubies)
        return if @options[:quiet]
        return unless @options[:estimate]
        run_interval = Puppet[:runinterval]
        active_nodes = active_node_count
        report_limit = @calculator::calculate_run_sample(active_nodes, run_interval)
        average_compile_time = average_compile_time(report_limit)
        maximum_nodes = @calculator::calculate_maximum_nodes(average_compile_time, total_puppetserver_jrubies, run_interval)
        minimum_jrubies = @calculator::calculate_minimum_jrubies(active_nodes, average_compile_time, run_interval)
        output _('Puppet Infrastructure Estimated Capacity')
        output_line
        output _("Found %{total_puppetserver_jrubies} available JRubies and %{active_nodes} active nodes.") % { total_puppetserver_jrubies: total_puppetserver_jrubies, active_nodes: active_nodes }
        output _("Found a run interval of %{run_interval} seconds and an average compile time of %{average_compile_time} seconds.") % { run_interval: run_interval, average_compile_time: average_compile_time }
        output _("A maximum of %{maximum_nodes} nodes can be served by %{total_puppetserver_jrubies} JRubies.") % { maximum_nodes: maximum_nodes, total_puppetserver_jrubies: total_puppetserver_jrubies }
        output _("A minimum of %{minimum_jrubies} JRubies are required to serve %{active_nodes} nodes.") % { minimum_jrubies: minimum_jrubies, active_nodes: active_nodes }
        output _('Note that available JRubies does not include the Primary Master when using Compile Masters.') if with_compile_masters?
        output_line
      end

      # Output an error and exit.

      def output_error_and_exit(message)
        Puppet.err(message)
        Puppet.err _("Rerun this command with '--debug' or '--help' for more information")
        exit 1
      end

      def output_pe_infrastructure_error_and_exit
        Puppet.err _('Puppet Infrastructure Summary: Unknown Infrastructure')
        Puppet.err _('Unable to find a Primary Master via a PuppetDB query')
        Puppet.err _('Verify PE Infrastructure node groups in the Console')
        Puppet.err _("Rerun this command with '--debug' or '--help' for more information")
        exit 1
      end

      def output_minimum_system_requirements_error_and_exit(certname)
        return if @options[:node] && node['certname'] != @options[:node]
        Puppet.err _("%{certname} does not meet the minimum system requirements") % { certname: certname }
        Puppet.err _("Rerun this command with '--debug' or '--help' for more information")
        exit 1
      end

      # Output a warning.

      def output_minimum_system_requirements_warning(node)
        return if @options[:node] && node['certname'] != @options[:node]
        output_warning _("# Found %{cpu} CPU(s) / %{ram} MB RAM for %{certname}") % { cpu: node['resources']['cpu'], ram: node['resources']['ram'], certname: node['certname'] }
        output_warning _("# This does not meet the minimum system requirements to calculate its settings without '--force'")
        output_line
      end

      def output_calculation_warning(node)
        return if @options[:node] && node['certname'] != @options[:node]
        output_warning _("# Found %{cpu} CPU(s) / %{ram} MB RAM for %{certname}") % { cpu: node['resources']['cpu'], ram: node['resources']['ram'], certname: node['certname'] }
        output_warning _("# Unable to calculate its settings")
        output_line
      end

      # PE-26994

      def autotunes_compilers?
        pe_2019_4_or_newer?
      end

      def output_autotune(node)
        return if @options[:node] && node['certname'] != @options[:node]
        output_warning _("# Found %{cpu} CPU(s) / %{ram} MB RAM for %{certname}") % { cpu: node['resources']['cpu'], ram: node['resources']['ram'], certname: node['certname'] }
        output_warning _("# This node is automatically tuned by Puppet Enterprise")
        output_line
      end

      def output_compilers_autotune
        if with_compilers? && autotunes_compilers?
          output _('This version of Puppet Enterprise optimizes tuning settings for PE Compilers (Compilers with Puppet Server and PuppetDB) by default')
          output _('Remove any tuning settings for PE Compilers defined in Hiera and/or the Classifier (Console) to use those default tuning settings.')
          output_line
        end
      end

      #
      # Identify
      #

      # Identify PE Infrastructure.

      def unknown_infrastructure?
        @nodes_with_role['primary_masters'].count.zero?
      end

      def monolithic?
        @nodes_with_role['console_hosts'].count.zero?
      end

      def with_ha?
        @nodes_with_role['replica_masters'].count > 0
      end

      def with_compile_masters?
        @nodes_with_role['compile_masters'].count > 0
      end

      def with_compilers?
        return false unless monolithic?
        return false unless with_compile_masters?
        with_puppetdb_on_all_masters?
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

      # Identify a PE Infrastructure node.

      def monolithic_master?(certname)
        monolithic? && @nodes_with_role['primary_masters'].include?(certname)
      end

      def replica_master?(certname)
        monolithic? && @nodes_with_role['replica_masters'].include?(certname)
      end

      def compile_master?(certname)
        @nodes_with_role['compile_masters'].include?(certname)
      end

      def compiler?(node)
        node['resources']['pp_auth_role'] == 'pe_compiler'
      end

      # Identify a class applied to a PE Infrastructure node.

      def node_with_class?(certname, classname)
        return false unless certname && classname
        @nodes_with_class[classname].count > 0 && @nodes_with_class[classname].include?(certname)
      end

      # Identify tunable classes applied to a PE Infrastructure node.

      def tunable_classes_for_node(certname)
        classes = {}
        tunable_class_names.each do |classname|
          classes[classname] = node_with_class?(certname, classname)
        end
        classes
      end

      # Identify the JRuby version on a PE Infrastructure node.
      # puppetserver::jruby_9k_enabled is a setting added to PE 2018.
      # puppetserver::jruby_jar is a setting added to PE 2017 and is outside the scope of this code.

      def with_jruby9k_enabled?(certname)
        # Avoid the fragile PuppetDB query (in current_settings_for_node) in older versions of PE.
        return false unless pe_2018_or_newer?
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

      # Identify available jrubies on a PE Infrastructure node.
      # Used when estimating PE Infrastructure capacity.

      def total_puppetserver_jrubies_for_node(certname, settings)
        return 0 unless settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances']
        default_jrubies = [resources_for_node(certname)['cpu'] - 1, 4].min
        settings['params']['puppet_enterprise::master::puppetserver::jruby_max_active_instances'] || default_jrubies
      end

      def total_puppetdb_connections_for_node(_certname, settings)
        return 0 unless settings['params']['puppet_enterprise::puppetdb::command_processing_threads']
        # https://github.com/puppetlabs/puppet-enterprise-modules/blob/irving/modules/puppet_enterprise/manifests/puppetdb.pp
        default_puppetdb_connections = 25 + [25, (settings['params']['puppet_enterprise::puppetdb::command_processing_threads'] * 2)].max
        unless settings['params']['puppet_enterprise::puppetdb::read_maximum_pool_size'] && settings['params']['puppet_enterprise::puppetdb::write_maximum_pool_size']
          return default_puppetdb_connections
        end
        settings['params']['puppet_enterprise::puppetdb::read_maximum_pool_size'] + settings['params']['puppet_enterprise::puppetdb::write_maximum_pool_size']
      end

      # Identify the current memory_per_jruby ratio on a PE Infrastructure node.
      # Used by the 'use_current_memory_per_jruby' option.

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

      # Verify minimum system requirements.
      # Can be overrided by the 'force' option.

      def meets_minimum_system_requirements?(resources)
        return true if @options[:force]
        # Round down (6144 -> 5678) account for vm overhead; see also fit_to_memory_percentage in calculate.rb.
        resources['cpu'] >= 2 && resources['ram'] >= 5678
      end

      # Versions
      # Allows mergeups in the PE implementation of this class.

      def pe_2018_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('5.5.0')
      end

      def pe_2019_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')
      end

      def pe_2019_2_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('6.9.0')
      end

      def pe_2019_4_or_newer?
        Gem::Version.new(Puppet.version) >= Gem::Version.new('6.14.0')
      end

      # Use to avoid querying PuppetDB.

      def using_inventory?
        @options[:local] || @options[:inventory]
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
  require 'puppet_x/puppetlabs/tune/inventory'
  require 'puppet_x/puppetlabs/tune/peconf'
  require 'puppet_x/puppetlabs/tune/query'
end
