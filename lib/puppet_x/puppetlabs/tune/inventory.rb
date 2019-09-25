require 'yaml'

# Notes:
#
# Mappings vary between PE Infrastructure roles, profiles, and classes.
# See: https://github.com/puppetlabs/puppetlabs-pe_infrastructure/blob/irving/lib/puppet_x/puppetlabs/meep/defaults.rb

module PuppetX
  module Puppetlabs
    # Query infrastructure and show current, or calculate optimized settings.
    class Tune
      # Use the local system or a file as inventory, instead of querying PuppeDB.
      class Inventory
        attr_reader :nodes
        attr_reader :roles
        attr_reader :classes

        def initialize
          @nodes   = {}
          @roles   = {}
          @classes = {}
        end

        # Inventory PE Infrastructure roles.

        def default_inventory_roles
          {
            'puppet_master_host'     => nil,
            'console_host'           => nil,
            'puppetdb_host'          => [],
            'database_host'          => [],
            'primary_master_replica' => nil,
            'compile_master'         => []
          }
        end

        # Inventory PE Infrastructure classes.

        def default_inventory_classes
          {
            'master'                 => [].to_set,
            'console'                => [].to_set,
            'puppetdb'               => [].to_set,
            'database'               => [].to_set,
            'amq::broker'            => [].to_set,
            'orchestrator'           => [].to_set,
            'primary_master'         => [].to_set,
            'primary_master_replica' => [].to_set,
            'compile_master'         => [].to_set
          }
        end

        # Use the local system to define a Monolithic PE Infrastructure node.
        # This eliminates the dependency upon PuppetDB during a clean install when there is no PuppetDB to query.

        def read_inventory_from_local_system
          Puppet.debug('Querying the local system to define a monolithic infrastructure master node')
          hostname = Puppet::Util::Execution.execute('hostname -f', 'combine' => false).chomp
          cpu = Puppet::Util::Execution.execute('nproc --all', 'combine' => false).chomp
          ram = Puppet::Util::Execution.execute('free -b | grep Mem', 'combine' => false).chomp.split(' ')[1]
          ram << 'b'
          nodes = {
            hostname => {
              'resources' => {
                'cpu' => cpu,
                'ram' => ram,
              }
            }
          }
          Puppet.debug("Found resources on the local system: #{nodes}")
          roles = {
            'puppet_master_host' => hostname
          }

          @nodes = nodes
          @roles = default_inventory_roles.merge(roles)
          @classes = default_inventory_classes
        end

        # Use an inventory file to define PE Infrastructure nodes.
        # This eliminates the dependency upon PuppetDB to query node resources and classes.
        # The compile_master, database_host, and puppetdb_host roles can be an Array or a String.

        def read_inventory_from_inventory_file(file)
          unless File.exist?(file)
            Puppet.err _("The inventory file %{file} does not exist") % { file: file }
            return
          end
          Puppet.debug("Using the inventory file #{file} to define infrastructure nodes")
          begin
            file_inventory = YAML.safe_load(File.read(file))
          rescue Psych::SyntaxError
            Puppet.err _("The inventory file %{file} contains a syntax error") % { file: file }
            return
          end
          unless file_inventory['nodes']
            Puppet.err _('The inventory file does not contain a nodes hash')
            return
          end
          file_inventory['roles'] = {} unless file_inventory['roles']
          file_inventory['roles']['compile_master'] = Array(file_inventory['roles']['compile_master'])
          file_inventory['roles']['database_host']  = Array(file_inventory['roles']['database_host'])
          file_inventory['roles']['puppetdb_host']  = Array(file_inventory['roles']['puppetdb_host'])

          @nodes = file_inventory['nodes']
          @roles = default_inventory_roles.merge(file_inventory['roles'])
          @classes = default_inventory_classes
        end

        # Convert inventory roles to PE Infrastructure classes, using Set instead of Array to prevent duplicates.

        def convert_inventory_roles_to_classes
          if @roles['database_host']
            @roles['database_host'].each do |database_host|
              Puppet.debug("Converting database_host role to classes for: #{database_host}")
              @classes['database'] << database_host
            end
          end

          if @roles['console_host']
            console_host = @roles['console_host']
            Puppet.debug("Converting console_host role to classes for: #{console_host}")
            @classes['console'] << console_host
          end

          is_split                = not_set?(@roles['console_host'])
          is_split_local_database = is_split && @roles['database_host'].count.zero?

          if @roles['puppetdb_host']
            @roles['puppetdb_host'].each do |puppetdb_host|
              Puppet.debug("Converting puppetdb_host role to classes for: #{puppetdb_host}")
              @classes['puppetdb'] << puppetdb_host
              @classes['database'] << @roles['puppetdb_host'].first if is_split_local_database
            end
          end

          is_mono                = is_split == false
          is_ha                  = not_set?(@roles['primary_master_replica'])
          is_mono_local_database = is_mono && @roles['database_host'].count.zero?
          is_mono_extra_large    = is_mono && !is_ha && @roles['database_host'].count == 1
          is_mono_ha_extra_large = is_mono && is_ha  && @roles['database_host'].count == 2
          is_extra_large         = is_mono_extra_large || is_mono_ha_extra_large

          if @roles['puppet_master_host']
            puppet_master_host = @roles['puppet_master_host']
            Puppet.debug("Converting puppet_master_host role to classes for: #{puppet_master_host}")
            @classes['primary_master'] << puppet_master_host
            @classes['master']         << puppet_master_host
            @classes['console']        << puppet_master_host if is_mono
            @classes['puppetdb']       << puppet_master_host if is_mono
            @classes['database']       << puppet_master_host if is_mono_local_database || is_extra_large
            @classes['amq::broker']    << puppet_master_host
            @classes['orchestrator']   << puppet_master_host
          end

          if @roles['primary_master_replica']
            primary_master_replica = @roles['primary_master_replica']
            Puppet.debug("Converting primary_master_replica role to classes for: #{primary_master_replica}")
            @classes['primary_master_replica'] << primary_master_replica
            @classes['master']                 << primary_master_replica
            @classes['console']                << primary_master_replica
            @classes['puppetdb']               << primary_master_replica
            @classes['database']               << primary_master_replica
            @classes['amq::broker']            << primary_master_replica
            @classes['orchestrator']           << primary_master_replica
          end

          if @roles['compile_master']
            @roles['compile_master'].each do |compile_master|
              Puppet.debug("Converting compile_master role to classes for: #{compile_master}")
              @classes['compile_master'] << compile_master
              @classes['master']         << compile_master
              @classes['puppetdb']       << compile_master if is_extra_large
            end
          end
        end

        #
        # Utilities
        #

        # Array or String

        def not_set?(variable)
          return false if variable.nil? || variable.empty?
          true
        end
      end
    end
  end
end
