def other_database_tunable_param_names
  [
    'puppet_enterprise::profile::database::autovacuum_max_workers',
    'puppet_enterprise::profile::database::autovacuum_work_mem',
    'puppet_enterprise::profile::database::effective_cache_size',
    'puppet_enterprise::profile::database::log_temp_files',
    'puppet_enterprise::profile::database::maintenance_work_mem',
    'puppet_enterprise::profile::database::work_mem'
  ]
end

def calculate_database_settings(node)
  percent_ram_shared_buffers         = 25
  minimum_ram_shared_buffers         = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
  maximum_ram_shared_buffers         = 16384
  percent_cpu_autovacuum_max_workers = 33.3
  minimum_cpu_autovacuum_max_workers = 3
  maximum_cpu_autovacuum_max_workers = 8
  minimum_ram_effective_cache_size   = 128
  maximum_ram_maintenance_work_mem   = 1024
  minimum_ram_work_mem               = 4
  maximum_ram_work_mem               = 16

  minimum_ram_os = (@options[:memory_reserved_for_os] != 0) ? @options[:memory_reserved_for_os] : @defaults[:memory_reserved_for_os]

  settings = initialize_host_settings(node)

  ram_shared_buffers = calculate_ram(node, settings['totals']['RAM']['used'], percent_ram_shared_buffers, minimum_ram_shared_buffers, maximum_ram_shared_buffers)
  return {} unless ram_shared_buffers
  settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_shared_buffers}MB"
  settings['totals']['RAM']['used'] += ram_shared_buffers

  # Subtract settings['totals']['RAM']['used'] from node['resources']['ram'] ?
  available_ram_mb = node['resources']['ram'] - minimum_ram_os
  available_ram_gb = (available_mb_for_cache_size / 1024.0).to_i

  # These are equivalent to the defaults in puppetlabs-puppet_enterprise/manifests/params.pp and puppetlabs-puppet_enterprise/manifests/profile/database.pp
  ram_work_mem               = clamp(minimum_ram_work_mem, ((available_ram_gb / 8.0) + 0.5).to_i, maximum_ram_work_mem)
  cpu_autovacuum_max_workers = calculate_cpu(node['resources']['cpu'], 0, percent_cpu_autovacuum_max_workers, minimum_cpu_autovacuum_max_workers, maximum_cpu_autovacuum_max_workers)
  ram_maintenance_work_mem   = [maximum_ram_maintenance_work_mem, (node['resources']['ram'] / 8.0).to_i].min
  ram_autovacuum_work_mem    = (ram_maintenance_work_mem / cpu_autovacuum_max_workers).to_i
  ram_effective_cache_size   = [((available_ram_mb * 3) / 5.0).to_i, minimum_ram_effective_cache_size].max
  log_temp_files             = (ram_work_mem * 1024) # specified in kilobytes # log_temp_files should equal work_mem to avoid logging temp files smaller than work_mem

  # shared_buffers: system memory < 2GB set to 20% of total system memory; < 64GB set to 25%; > 64GB set to 16GB
  # maintenance_work_mem: 10% of system memory, up to 1GB
  # effective_cache_size: 75% of system memory

  settings['params']['puppet_enterprise::profile::database::autovacuum_max_workers'] = cpu_autovacuum_max_workers
  settings['params']['puppet_enterprise::profile::database::autovacuum_work_mem']    = "#{ram_autovacuum_work_mem}MB"
  settings['params']['puppet_enterprise::profile::database::effective_cache_size']   = "#{ram_effective_cache_size}MB"
  settings['params']['puppet_enterprise::profile::database::log_temp_files']         = log_temp_files
  settings['params']['puppet_enterprise::profile::database::maintenance_work_mem']   = "#{ram_maintenance_work_mem}MB"
  settings['params']['puppet_enterprise::profile::database::work_mem']               = "#{ram_work_mem}MB"

  settings
end
