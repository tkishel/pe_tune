def calculate_database_settings(node)
  percent_ram_database = 25
  minimum_ram_database = fit_to_memory(node['resources']['ram'], 2048, 3072, 4096)
  maximum_ram_database = 16384

  settings = initialize_host_settings(node)

  ram_database = calculate_ram(node, database_settings['totals']['RAM']['used'], percent_ram_database, minimum_ram_database, maximum_ram_database)
  return {} unless ram_database
  settings['params']['puppet_enterprise::profile::database::shared_buffers'] = "#{ram_database}MB"
  settings['totals']['RAM']['used'] += ram_database

  available_gb_for_postgres  = (settings['totals']['RAM']['used'] / 1024)
  cpu_autovacuum_max_workers = [3, [8, (node['resources']['cpu'] / 3).to_i].min].max
  ram_effective_cache_size   = [((available_ram_for_postgres * 3) / 5).to_i, 128].max
  ram_maintenance_work_mem   = (available_ram_for_postgres / 8).to_i
  ram_autovacuum_work_mem    = (ram_maintenance_work_mem / cpu_autovacuum_max_workers).to_i
  ram_work_mem               = clamp(4, ((available_gb_for_postgres / 8.0) + 0.5).to_i, 16)
  log_temp_files             = (ram_work_mem * 1024)

  settings['params']['puppet_enterprise::profile::database::autovacuum_max_workers'] = cpu_autovacuum_max_workers
  settings['params']['puppet_enterprise::profile::database::autovacuum_work_mem']    = "#{ram_autovacuum_work_mem}MB"
  settings['params']['puppet_enterprise::profile::database::effective_cache_size']   = "#{ram_effective_cache_size}MB"
  settings['params']['puppet_enterprise::profile::database::log_temp_files']         = log_temp_files
  settings['params']['puppet_enterprise::profile::database::maintenance_work_mem']   = "#{ram_maintenance_work_mem}MB"
  settings['params']['puppet_enterprise::profile::database::work_mem']               = "#{ram_work_mem}MB"

  # Do not add the following, as they are not allocations: cpu_autovacuum_max_workers, log_temp_files, ram_effective_cache_size
  settings['totals']['RAM']['used'] += ram_buffers + ram_work_mem + ram_maintenance_work_mem + (ram_autovacuum_work_mem * cpu_autovacuum_max_workers)

  settings
end
