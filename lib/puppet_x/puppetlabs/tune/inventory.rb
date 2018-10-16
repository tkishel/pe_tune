require 'yaml'

# Notes:
#
# Mappings vary between roles, profiles, and classes.
# See: https://github.com/puppetlabs/puppetlabs-pe_infrastructure/blob/irving/lib/puppet_x/puppetlabs/meep/defaults.rb

module PuppetX
  module Puppetlabs
    # Tune optimized settings.
    class Tune
      # Use the local system or a file as inventory.
      class Inventory

        attr_reader :nodes
        attr_reader :roles
        attr_reader :classes

        # Inventory infrastructure roles.

        def default_inventory_roles
          {
            'puppet_master_host'     => nil,
            'console_host'           => nil,
            'puppetdb_host'          => [],
            'database_host'          => nil,
            'primary_master_replica' => nil,
            'compile_master'         => []
          }
        end

        # Inventory infrastructure classes.

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

        # Use the local system to define a monolithic infrastructure master node.
        # This eliminates the dependency upon PuppetDB to query node resources and classes.

        def read_inventory_from_local_system
          Puppet.debug _('Querying the local system to define a monolithic infrastructure master node')
          hostname = Puppet::Util::Execution.execute('hostname -f').chomp
          cpu = Puppet::Util::Execution.execute('nproc --all').chomp
          ram = Puppet::Util::Execution.execute('free -b | grep Mem').chomp.split(' ')[1]
          ram << 'b'
          nodes = {
            hostname => {
              'resources' => {
                'cpu' => cpu,
                'ram' => ram,
              }
            }
          }
          Puppet.debug _("Found resources on the local system: %{nodes}") % { nodes: nodes }
          roles = {
            'puppet_master_host' => hostname
          }

          @nodes = nodes
          @roles = default_inventory_roles.merge(roles)
          @classes = default_inventory_classes
          convert_inventory_roles_to_classes
        end

        # Use an inventory file to define infrastructure nodes.
        # This eliminates the dependency upon PuppetDB to query node resources and classes.
        # The compile_master and puppetdb_host roles can be an Array or a String.

        def read_inventory_from_inventory_file(file)
          unless File.exist?(file)
            Puppet.err _("The inventory file %{file} does not exist") % { file: file }
            return
          end
          Puppet.debug _("Using the inventory file %{file} to define infrastructure nodes") % { file: file }
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
          file_inventory['roles']['puppetdb_host']  = Array(file_inventory['roles']['puppetdb_host'])

          @nodes = file_inventory['nodes']
          @roles = default_inventory_roles.merge(file_inventory['roles'])
          @classes = default_inventory_classes
          convert_inventory_roles_to_classes
        end

        # Convert inventory roles to classes, using Set instead of Array to prevent duplicates.

        def convert_inventory_roles_to_classes
          if @roles['database_host']
            database_host = @roles['database_host']
            Puppet.debug _("Converting database_host role to classes for: %{host}") % { host: database_host }
            @classes['database'] << database_host
          end

          if @roles['puppetdb_host']
            @roles['puppetdb_host'].each do |puppetdb_host|
            Puppet.debug _("Converting puppetdb_host role to classes for: %{host}") % { host: puppetdb_host }
              @classes['puppetdb'] << puppetdb_host
              @classes['database'] << @roles['puppetdb_host'].first if nil_or_empty?(@roles['database_host'])
            end
          end

          if @roles['console_host']
            console_host = @roles['console_host']
            Puppet.debug _("Converting console_host role to classes for: %{host}") % { host: console_host }
            @classes['console'] << console_host
          end

          if @roles['puppet_master_host']
            puppet_master_host = @roles['puppet_master_host']
            Puppet.debug _("Converting puppet_master_host role to classes for: %{host}") % { host: puppet_master_host }
            @classes['primary_master'] << puppet_master_host
            @classes['master']         << puppet_master_host
            @classes['console']        << puppet_master_host if nil_or_empty?(@roles['console_host'])
            @classes['puppetdb']       << puppet_master_host if nil_or_empty?(@roles['puppetdb_host'])
            @classes['database']       << puppet_master_host if nil_or_empty?(@roles['puppetdb_host']) && nil_or_empty?(@roles['database_host'])
            @classes['amq::broker']    << puppet_master_host
            @classes['orchestrator']   << puppet_master_host
          end

          if @roles['primary_master_replica']
            primary_master_replica = @roles['primary_master_replica']
            Puppet.debug _("Converting primary_master_replica role to classes for: %{host}") % { host: primary_master_replica }
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
              Puppet.debug _("Converting compile_master role to classes for: %{host}") % { host: compile_master }
              @classes['compile_master'] << compile_master
              @classes['master']         << compile_master
            end
          end
        end

        #
        # Utilities
        #

        # Array or String

        def nil_or_empty?(variable)
          return true if variable.nil? || variable.empty?
          false
        end
      end
    end
  end
end
