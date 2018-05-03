#!/opt/puppetlabs/puppet/bin/ruby

require 'facter'
require 'json'
require 'yaml'

# SUMMARY:
#
# This script tunes each of the settings documented in tuning_monolithic.
# https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html
#
# It does not tune the following settings calcuated in puppetlabs-puppet_enterprise.
# autovacuum_max_workers, autovacuum_work_mem, effective_cache_size, maintenance_work_mem, work_mem

# TODO: LIST
#
# Verify the equations and default values in the calculate_ methods.
# Replace/remove the unit test workaround.

module PuppetX
  module Puppetlabs
    # Query infrastructure and calculate optimized settings.
    class Tune
      def initialize(options)
        # TODO: Replace/remove this unit test workaround.
        return if options[:unit_test]

        @no_minimum_system_requirements = options[:force]

        @hiera_output_path = options[:hiera]
        @hocon_output_path = options[:hocon]
        @hocon_settings = {}

        @configuration = PuppetX::Puppetlabs::Configuration.new
        @infrastructure = PuppetX::Puppetlabs::Infrastructure.new
        @puppetdb = PuppetX::Puppetlabs::Puppetdb.new

        @replica_masters = @puppetdb.replica_masters
        @primary_masters = @puppetdb.primary_masters
        @compile_masters = @puppetdb.compile_masters
        @console_hosts   = @puppetdb.console_hosts
        @puppetdb_hosts  = @puppetdb.puppetdb_hosts
        @database_hosts  = @puppetdb.database_hosts

        @pe_database_host = @infrastructure.pe_conf_database_host
      end

      # Methods requiring @instance variables to access class instance methods.

      def write_pe_conf
        return unless @hocon_output_path
        return if @hocon_settings.empty?
        @infrastructure::write_pe_conf(@hocon_output_path, @hocon_settings)
      end

      def get_resources_for_node(certname)
        resources = {}
        resources['cpu'] = @puppetdb::get_cpu_for_node(certname)
        resources['ram'] = @puppetdb::get_ram_for_node(certname)
        resources
      end

      # Identify infrastructure.

      def unknown_pe_infrastructure?
        @primary_masters.count.zero?
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
          @puppetdb_hosts.count > 0 && @puppetdb_hosts.include?(@pe_database_host) == false
        end
      end

      def with_ha?
        @replica_masters.count > 0
      end

      # Identify infrastructure hosts by profile.
      # Calculate optimized settings based upon each profile's specific set of services.
      #
      # Alternative:
      # Identify all infrastructure hosts.
      # Calculate optimized settings based upon each host's specific set of services.

      def output_optimized_settings
        if unknown_pe_infrastructure?
          output_pe_infrastructure_unknown
          return
        end

        monolithic = monolithic?
        with_compile_masters = with_compile_masters?
        with_external_postgresql = with_external_postgresql?

        make_optional_output_directories

        output_pe_infrastucture_totals(monolithic, with_compile_masters, with_external_postgresql)
        output_primary_masters(@primary_masters, monolithic, with_compile_masters, with_external_postgresql)
        output_replica_masters(@replica_masters, with_compile_masters, with_external_postgresql)
        unless monolithic
          output_console_hosts(@console_hosts)
          output_puppetdb_hosts(@puppetdb_hosts, with_external_postgresql)
        end
        output_compile_masters(@compile_masters) if with_compile_masters
        output_external_postgresql_host(@pe_database_host) if with_external_postgresql

        write_pe_conf
      end

      # Primary Master: Applicable to Monolithic and Split Infrastructures.

      def output_primary_masters(servers, monolithic, with_compile_masters, with_external_postgresql)
        profile = 'Primary Master'
        servers.each do |certname|
          resources = get_resources_for_node(certname)
          output_resources(certname, resources, profile)
          if monolithic
            settings, totals = calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          else
            with_activemq = true
            with_orchestrator = true
            settings, totals = calculate_master_settings(resources, with_activemq, with_orchestrator)
          end
          output_settings(certname, settings, totals)
        end
      end

      # Replica Master: Applicable to Monolithic Infrastructures.

      def output_replica_masters(servers, with_compile_masters, with_external_postgresql)
        profile = 'Replica Master'
        servers.each do |certname|
          resources = get_resources_for_node(certname)
          output_resources(certname, resources, profile)
          settings, totals = calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
          output_settings(certname, settings, totals)
        end
      end

      # Compile Master: Applicable to Monolithic and Split Infrastructures.

      def output_compile_masters(servers)
        profile = 'Compile Master'
        servers.each do |certname|
          resources = get_resources_for_node(certname)
          output_resources(certname, resources, profile)
          with_activemq = false
          with_orchestrator = false
          settings, totals = calculate_master_settings(resources, with_activemq, with_orchestrator)
          output_settings(certname, settings, totals)
        end
      end

      # Console Host: Specific to Split Infrastructures. By default, a list of one.

      def output_console_hosts(servers)
        profile = 'Console Host'
        servers.each do |certname|
          resources = get_resources_for_node(certname)
          output_resources(certname, resources, profile)
          settings, totals = calculate_console_settings(resources)
          output_settings(certname, settings, totals)
        end
      end

      # PuppetDB Host: Specific to Split Infrastructures. By default, a list of one.

      def output_puppetdb_hosts(servers, with_external_postgresql)
        profile = 'PuppetDB Host'
        servers.each do |certname|
          resources = get_resources_for_node(certname)
          output_resources(certname, resources, profile)
          settings, totals = calculate_puppetdb_settings(resources, with_external_postgresql)
          output_settings(certname, settings, totals)
        end
      end

      # External PostgreSQL Host: Applicable to Monolithic and Split Infrastructures.

      def output_external_postgresql_host(certname)
        profile = 'External PostgreSQL Host'
        resources = get_resources_for_node(certname)
        output_resources(certname, resources, profile)
        settings, totals = calculate_external_postgresql_settings(resources)
        output_settings(certname, settings, totals)
      end

      # Consolidate output.

      def output(info)
        puts info
      end

      def output_pe_infrastructure_unknown
        output("### Puppet Infrastructure Summary: Unknown Infrastructure\n\n")
        output('## Error: Unable to find Infrastructure Hosts via PuppetDB query.')
        output("## Please verify PE Infrastructure node groups in the Console.\n\n")
      end

      def output_pe_infrastucture_totals(monolithic, with_compile_masters, with_external_postgresql)
        type = monolithic ? 'Monolithic' : 'Split'
        w_cm = with_compile_masters ? ' with Compile Masters' : ''
        w_ep = with_external_postgresql ? ' with External PostgreSQL' : ''
        output("### Puppet Infrastructure Summary: Found a #{type} Infrastructure#{w_cm}#{w_ep}\n\n")
      end

      def output_resources(certname, resources, profile)
        output("## Found: #{resources['cpu']} CPU(s) / #{resources['ram']} MB RAM for #{profile} #{certname}")
      end

      def output_totals(certname, totals)
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
      end

      def output_minimum_system_requirements_error(certname)
        output("## Error: #{certname} does not meet the minimum system requirements to calculate settings\n\n")
      end

      # Create directories for output to files, or unset the associated variable.

      def make_optional_output_directories
        @hiera_output_path = make_optional_output_directory(@hiera_output_path)
        @hocon_output_path = make_optional_output_directory(@hocon_output_path)
      end

      # Create the directory for output to files, or return nil.

      def make_optional_output_directory(directory)
        return nil unless directory
        return directory if File.directory?(directory)
        Dir.mkdir(directory)
        unless File.directory?(directory)
          output("## Error: Unable to create output directory: #{directory}\n\n")
          return nil
        end
        directory
      end

      # Output to Hiera and accumulate HOCON.

      def output_settings(certname, settings, totals)
        if settings.empty?
          output_minimum_system_requirements_error(certname)
          return
        end
        output_settings_to_hiera(certname, settings)
        append_settings_to_hocon(certname, settings)
        output_totals(certname, totals)
      end

      # Output to STDOUT or Hiera YAML files.

      def output_settings_to_hiera(certname, settings)
        return if settings.empty?
        settings_yaml = settings.to_yaml
        if @hiera_output_path
          output_file = "#{@hiera_output_path}/#{certname}.yaml"
          File.write(output_file, settings_yaml)
          output("## Wrote Hiera YAML file: #{output_file}\n\n")
        else
          output("## Specify the following in Hiera in nodes/#{certname}.yaml\n\n")
          output(settings_yaml)
          output("\n")
        end
      end

      # Accumulate HOCON for output by write_pe_conf aka Puppet::Util::Pe_conf.save().

      def append_settings_to_hocon(certname, settings)
        return if settings.empty?
        @hocon_settings[certname] = settings
      end

      # Verify minimum system requirements.

      def node_meets_minimum_system_requirements?(resources)
        return true if @no_minimum_system_requirements
        (resources['cpu'] >= 4 && resources['ram'] >= 8192)
      end

      # Calculon Compute!

      # Primary Masters in Monolithic Infrastructures.
      # Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.
      #
      # percent_cpu_threads        based upon tuning_monolithic;                                            see also config_puppetdb
      # minimum_cpu_jrubies        based upon tuning_monolithic
      # maximum_cpu_jrubies        based upon tuning_monolithic
      # minimum_cpu_threads        based upon tuning_monolithic
      # maximum_cpu_threads        based upon tuning_monolithic
      # minimum_mb_puppetserver    based upon tuning_monolithic
      # mb_per_puppetserver_jruby  based upon tuning_monolithic: changed from 512 to 512,768,1024;          see also config_puppetserver
      # mb_puppetserver_code_cache based upon puppetlabs-puppet_enterprise/.../manifests/params.pp
      # percent_mb_puppetdb        based upon tuning_monolithic
      # minimum_mb_puppetdb        based upon tuning_monolithic: changed from 256,2048 to 512,1024,2048;    see also config_java_args: 512
      # maximum_mb_puppetdb        based upon tuning_monolithic: changed from 6144 to 8192
      # percent_mb_buffers         recommended by postgresql
      # minimum_mb_buffers         based upon tuning_monolithic: changed from 2048,4096 to 2048,3072,4096
      # maximum_mb_buffers         recommended by postgresql
      # mb_console                 based upon tuning_monolithic; changed from 256,512,1024 to 512,768,1024; see also config_java_args: 512
      # mb_orchestrator            based upon tuning_monolithic: changed from 192,384,768 to 512,768,1024;  see also config_java_args: 1024
      # mb_activemq                based upon tuning_monolithic;                                            see also config_java_args: 1024
      # reserve_mb_os              estimated by support
      # minimum_mb_g1gc            estimated by support
      #
      # Note: In 2018.x, JRuby 9K uses an additional 128MB of RAM compared to earlier versions.

      def calculate_monolithic_master_settings(resources, with_compile_masters, with_external_postgresql)
        return [{}, {}] unless node_meets_minimum_system_requirements?(resources)

        percent_cpu_threads        = with_compile_masters ? 75 : 25
        minimum_cpu_jrubies        = 2
        maximum_cpu_jrubies        = fit_to_processors(resources['cpu'], 2, 6, 10)
        minimum_cpu_threads        = 2
        maximum_cpu_threads        = fit_to_processors(resources['cpu'], 2, 6, 10)
        minimum_mb_puppetserver    = with_compile_masters ? 1024 : 2048
        mb_per_puppetserver_jruby  = fit_to_memory(resources['ram'], 512, 768, 1024)
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
        reserve_mb_os              = 1024
        # minimum_mb_g1gc            = 2048

        minimum_mb_buffers         = 0 if with_external_postgresql
        mb_puppetserver_code_cache = 0 unless jruby_9k_enabled?

        settings = {}
        totals = {}

        if with_external_postgresql
          mb_buffers = 0
        else
          available_mb_for_buffers = resources['ram'] - reserve_mb_os
          if available_mb_for_buffers < minimum_mb_buffers
            return [{}, {}]
          end
          mb_buffers = percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
        end

        command_processing_threads = percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)

        available_mb_for_puppetdb = resources['ram'] - reserve_mb_os - mb_buffers
        if available_mb_for_puppetdb < minimum_mb_puppetdb
          return [{}, {}]
        end

        mb_puppetdb = percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
        java_args_for_puppetdb = { 'Xms' => "#{mb_puppetdb}m", 'Xmx' => "#{mb_puppetdb}m" }
        # java_args_for_puppetdb['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_puppetdb >= minimum_mb_g1gc)

        available_mb_for_puppetserver = resources['ram'] - reserve_mb_os - mb_buffers - mb_puppetdb - mb_console - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
        if available_mb_for_puppetserver < minimum_mb_puppetserver
          return [{}, {}]
        end

        jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
        jruby_max_active_instances = percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)

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
        settings['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if jruby_9k_enabled?
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
      # Calculate the number of jrubies by the number of jrubies that will fit into RAM rather than CPU.
      #
      # minimum_cpu_jrubies        recommended by support
      # maximum_cpu_jrubies        based upon config_puppetserver
      # minimum_mb_puppetserver    based upon tuning_monolithic;
      # mb_per_puppetserver_jruby  based upon tuning_monolithic: changed from 512 to 512,768,1024;         see also config_puppetserver
      # mb_puppetserver_code_cache based upon puppetlabs-puppet_enterprise/.../manifests/params.pp
      # mb_orchestrator            based upon tuning_monolithic: changed from 192,384,768 to 512,768,1024; see also config_java_args: 1024
      # mb_activemq                based upon tuning_monolithic;                                           see also config_java_args: 1024
      # reserve_mb_os              estimated by support
      # minimum_mb_g1gc            estimated by support

      def calculate_master_settings(resources, with_activemq, with_orchestrator)
        return [{}, {}] unless node_meets_minimum_system_requirements?(resources)

        minimum_cpu_jrubies        = 1
        maximum_cpu_jrubies        = resources['cpu'] - 1
        minimum_mb_puppetserver    = 1024
        mb_per_puppetserver_jruby  = fit_to_memory(resources['ram'], 512, 768, 1024)
        mb_puppetserver_code_cache = (resources['ram'] < 2048) ? 48 : 512
        mb_orchestrator            = fit_to_memory(resources['ram'], 512, 768, 1024)
        mb_activemq                = fit_to_memory(resources['ram'], 512, 1024, 2048)
        reserve_mb_os              = 1024
        # minimum_mb_g1gc            = 2048

        mb_orchestrator            = with_orchestrator ? mb_orchestrator : 0
        mb_activemq                = with_activemq     ? mb_activemq     : 0
        mb_puppetserver_code_cache = 0 unless jruby_9k_enabled?

        settings = {}
        totals = {}

        available_mb_for_puppetserver = resources['ram'] - reserve_mb_os - mb_orchestrator - mb_activemq - mb_puppetserver_code_cache
        if available_mb_for_puppetserver < minimum_mb_puppetserver
          return [{}, {}]
        end

        jrubies_by_mb = (available_mb_for_puppetserver / mb_per_puppetserver_jruby).to_i
        jruby_max_active_instances = percent_of_resource(jrubies_by_mb, 100, minimum_cpu_jrubies, maximum_cpu_jrubies)
        settings['puppet_enterprise::master::jruby_max_active_instances'] = jruby_max_active_instances

        settings['puppet_enterprise::master::puppetserver::reserved_code_cache'] = "#{mb_puppetserver_code_cache}m" if jruby_9k_enabled?

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
      #
      # percent_mb_console recommended by support
      # minimum_mb_console based upon tuning_monolithic; changed from 256,512,1024 to 512,768,1024; see also config_java_args: 512
      # maximum_mb_console recommended by support
      # reserve_mb_os      estimated by support
      # minimum_mb_g1gc    estimated by support

      def calculate_console_settings(resources)
        return [{}, {}] unless node_meets_minimum_system_requirements?(resources)

        percent_mb_console = 75
        minimum_mb_console = fit_to_memory(resources['ram'], 512, 768, 1024)
        maximum_mb_console = 4096
        reserve_mb_os      = 1024
        # minimum_mb_g1gc    = 2048

        settings = {}
        totals = {}

        available_mb_for_console = resources['ram'] - reserve_mb_os
        if available_mb_for_console < minimum_mb_console
          return [{}, {}]
        end

        mb_console = percent_of_resource(resources['ram'], percent_mb_console, minimum_mb_console, maximum_mb_console)
        java_args_for_console = { 'Xms' => "#{mb_console}m", 'Xmx' => "#{mb_console}m" }
        # java_args_for_console['XX:+UseG1GC'] = '' if (jruby_9k_enabled? == false) && (mb_console >= minimum_mb_g1gc)
        settings['puppet_enterprise::profile::console::java_args'] = java_args_for_console

        ram_used = mb_console
        totals['RAM'] = { 'total' => resources['ram'], 'used' => ram_used }

        [settings, totals]
      end

      # PuppetDB Hosts in Split Infrastructures.
      # Assumes that pe-puppetdb and (by default) pe-postgresql are the only services on the host.
      #
      # percent_cpu_threads based upon tuning_monolithic; see also config_puppetdb
      # minimum_cpu_threads recommended by support
      # maximum_cpu_threads recommended by support
      # percent_mb_puppetdb based upon tuning_monolithic
      # percent_mb_buffers  recommended by postgresql
      # minimum_mb_puppetdb based upon tuning_monolithic: changed from 256,2048 to 512,1024,2048; see also config_java_args: 512
      # maximum_mb_puppetdb based upon tuning_monolithic: changed from 6144 to 8192
      # minimum_mb_buffers  based upon tuning_monolithic: changed from 2048,4096 to 2048,3072,4096
      # maximum_mb_buffers  recommended by postgresql
      # reserve_mb_os       estimated by support
      # minimum_mb_g1gc     estimated by support

      def calculate_puppetdb_settings(resources, with_external_postgresql)
        return [{}, {}] unless node_meets_minimum_system_requirements?(resources)

        percent_cpu_threads = 75
        minimum_cpu_threads = 1
        maximum_cpu_threads = resources['cpu'] - 1
        percent_mb_puppetdb = with_external_postgresql ? 50 : 25
        percent_mb_buffers  = with_external_postgresql ? 0  : 25
        minimum_mb_puppetdb = fit_to_memory(resources['ram'], 512, 1024, 2048)
        maximum_mb_puppetdb = 8192
        minimum_mb_buffers  = fit_to_memory(resources['ram'], 2048, 3072, 4096)
        maximum_mb_buffers  = 16384
        reserve_mb_os       = 1024
        # minimum_mb_g1gc     = 2048

        minimum_mb_buffers = with_external_postgresql ? 0 : minimum_mb_buffers

        settings = {}
        totals = {}

        if with_external_postgresql
          mb_buffers = 0
        else
          available_mb_for_buffers = resources['ram'] - reserve_mb_os
          if available_mb_for_buffers < minimum_mb_buffers
            return [{}, {}]
          end
          mb_buffers = percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
          settings['puppet_enterprise::profile::database::shared_buffers'] = "#{mb_buffers}MB"
        end

        command_processing_threads = percent_of_resource(resources['cpu'], percent_cpu_threads, minimum_cpu_threads, maximum_cpu_threads)
        settings['puppet_enterprise::puppetdb::command_processing_threads'] = command_processing_threads

        available_mb_for_puppetdb = resources['ram'] - reserve_mb_os - mb_buffers

        if available_mb_for_puppetdb < minimum_mb_puppetdb
          return [{}, {}]
        end

        mb_puppetdb = percent_of_resource(resources['ram'], percent_mb_puppetdb, minimum_mb_puppetdb, maximum_mb_puppetdb)
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
      # Assume that pe-postgresql is the only service on the host.
      #
      # percent_mb_buffers recommended by postgresql
      # minimum_mb_buffers based upon tuning_monolithic, changed from 2048,4096 to 2048,3072,4096
      # maximum_mb_buffers recommended by postgresql
      # reserve_mb_os      estimated by support
      # minimum_mb_g1gc    estimated by support

      def calculate_external_postgresql_settings(resources)
        return [{}, {}] unless node_meets_minimum_system_requirements?(resources)

        percent_mb_buffers = 25
        minimum_mb_buffers = fit_to_memory(resources['ram'], 2048, 3072, 4096)
        maximum_mb_buffers = 16384
        reserve_mb_os      = 1024

        settings = {}
        totals = {}

        available_mb_for_buffers = resources['ram'] - reserve_mb_os
        if available_mb_for_buffers < minimum_mb_buffers
          return [{}, {}]
        end

        mb_buffers = percent_of_resource(resources['ram'], percent_mb_buffers, minimum_mb_buffers, maximum_mb_buffers)
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
        return large  if processors >= 16
      end

      # Model https://puppet.com/docs/pe/latest/configuring/tuning_monolithic.html

      def fit_to_memory(memory, small, medium, large)
        return small  if memory <= 8192
        return medium if memory <= 16384
        return medium if memory <  32768
        return large  if memory >= 32768
      end

      # Return a percentage of a resource within a minimum and maximum.
      # AKA: clamp_percent_of_resource
      # Alternative: [minimum, resource_percentage, maximum].sort[1]

      def percent_of_resource(resource, percentage, minimum, maximum)
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

      # JRuby 9K is the default in 2018.x.

      def jruby_9k_enabled?
        pe_server_version = Facter.value('pe_server_version') || 'NOT_NIL'
        pe_server_version.start_with? '2018'
      end
    end
  end
end

# The following allows this library to be executed as a standalone script, during initial development.

if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  require 'hocon'
  require 'optparse'
  require 'puppet'
  require 'puppet/util/puppetdb'

  module PuppetX
    module Puppetlabs
      # This class is identical to: lib/puppet_x/configuration.rb
      class Configuration
        attr_reader :puppet_conf_server

        def initialize
          read_primary_master
        end

        def read_primary_master
          Puppet.debug("Reading: #{Puppet[:config]}")
          not_primary_master = Puppet[:certname] != Puppet[:server]
          if not_primary_master
            Puppet.err('This command must be run on the Primary Master')
            exit 1
          end
          @puppet_conf_server = Puppet[:server]
          Puppet.debug("Found puppet.conf server: #{@puppet_conf_server}")
        end
      end

      # This class is an alternative to: lib/puppet_x/infrastructure.rb
      class Infrastructure
        attr_reader :pe_conf
        attr_reader :pe_conf_puppet_master_host
        attr_reader :pe_conf_puppetdb_host
        attr_reader :pe_conf_database_host

        def initialize
          read_pe_conf
        end

        def read_pe_conf
          pe_conf_file = '/etc/puppetlabs/enterprise/conf.d/pe.conf'
          Puppet.debug("Reading: #{pe_conf_file}")
          if File.exist?(pe_conf_file)
            Puppet.debug("Found: #{pe_conf_file}")
            @pe_conf = Hocon.load(pe_conf_file)
          else
            Puppet.err("Error: File does not exist: #{pe_conf_file}")
            @pe_conf = {}
          end
          @pe_conf_puppet_master_host = @pe_conf['puppet_enterprise::puppet_master_host'] || Puppet[:certname]
          @pe_conf_puppet_master_host = Puppet[:certname] if pe_conf_puppet_master_host == '%{::trusted.certname}'
          @pe_conf_puppetdb_host = @pe_conf['puppet_enterprise::puppetdb_host'] || @pe_conf_puppet_master_host
          @pe_conf_database_host = @pe_conf['puppet_enterprise::database_host'] || @pe_conf_puppetdb_host
          Puppet.debug("Found pe.conf puppet_master_host: #{@pe_conf_puppet_master_host}")
          Puppet.debug("Found pe.conf pe_puppetdb_host: #{@pe_conf_puppetdb_host}")
          Puppet.debug("Found pe.conf pe_database_host: #{@pe_conf_database_host}")
        end

        def write_pe_conf(_directory, _settings)
          Puppet.debug('Error: Cannot load puppet/util/pe_conf via a standalone script, as its not in vendor_ruby.')
        end
      end

      # This class is an alternative to: lib/puppet_x/puppetdb.rb.
      class Puppetdb
        attr_reader :environment
        attr_reader :replica_masters
        attr_reader :primary_masters
        attr_reader :compile_masters
        attr_reader :console_hosts
        attr_reader :puppetdb_hosts
        attr_reader :database_hosts

        def initialize
          # PE-15116 results in Puppet[:environment] == 'enterprise' in the infrastructure face.
          @environment = Puppet[:environment]
          @replica_masters = get_pe_infra_nodes_by_class('Primary_master_replica', @environment)
          @primary_masters = get_pe_infra_nodes_by_class('Certificate_authority', @environment) - @replica_masters
          @compile_masters = get_pe_infra_nodes_by_class('Master', @environment)   - @primary_masters - @replica_masters
          @console_hosts   = get_pe_infra_nodes_by_class('Console', @environment)  - @primary_masters - @replica_masters
          @puppetdb_hosts  = get_pe_infra_nodes_by_class('Puppetdb', @environment) - @primary_masters - @replica_masters
          @database_hosts  = get_pe_infra_nodes_by_class('Database', @environment) - @primary_masters - @replica_masters
        end

        def get_cpu_for_node(certname)
          # Testing workaround.
          return ENV['TEST_CPU'].to_i if ENV['TEST_CPU']
          results = get_fact_for_node(certname, 'processors', @environment)
          return 0 unless results
          results['count'].to_i
        end

        def get_ram_for_node(certname)
          # Testing workaround.
          return ENV['TEST_RAM'].to_i if ENV['TEST_RAM']
          results = get_fact_for_node(certname, 'memory', @environment)
          return 0 unless results
          (results['system']['total_bytes'].to_i / 1024 / 1024).to_i
        end

        def get_pe_infra_nodes_by_class(class_name, environment = 'production')
          Puppet.debug("Querying PuppetDB for Class: Puppet_enterprise::Profile::#{class_name}")
          pql = ['from', 'resources',
                  ['extract', ['certname', 'parameters'],
                    ['and',
                      ['=', 'environment', environment],
                      ['=', ['node', 'active'], true],
                      ['=', 'type', 'Class'],
                      ['=', 'title', "Puppet_enterprise::Profile::#{class_name}"]
                    ]
                  ]
                ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          Puppet.debug(results)
          results.map { |resource| resource.fetch('certname') }
        end

        def get_fact_for_node(certname, fact_name, environment = 'production')
          Puppet.debug("Querying PuppetDB for Fact: #{certname} #{fact_name}")
          pql = ['from', 'facts',
                  ['extract', ['name', 'value'],
                    ['and',
                      ['=', 'environment', environment],
                      ['=', ['node', 'active'], true],
                      ['=', 'certname', certname],
                      ['=', 'name', fact_name]
                    ]
                  ]
                ]
          results = Puppet::Util::Puppetdb.query_puppetdb(pql)
          return if results.empty?
          Puppet.debug(results)
          return unless results.first['value']
          results.first['value']
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
    opts.on('--hiera DIRECTORY', 'Optional output directory for settings as Hiera YAML files') do |h|
      options[:hiera] = h
    end
    options[:debug] = false
    opts.on('--debug', 'Enable logging of debug information') do
      options[:debug] = true
    end
    options[:force] = false
    opts.on('--force', 'Do not enforce minimum system requirements') do
      options[:force] = true
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
  Tune.output_optimized_settings
end
