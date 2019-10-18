# Changelog

All notable changes to this project will be documented in this file.

# 3.0.2

- Define an intuitive output order
- Improve documentation

# 3.0.1

- Convert puppetserver from percent to remainder of unallocated processors
- Remove database settings not based upon resources
- Document formulas used
- Output common data as data
- Simplify spec test math
- Drop percent_clamp

# 3.0.0

- Convert calculations to percentages

# 2.4.2

- Improve debugging output
- Replace the concept of PE XL with PE Compilers
- Set log_temp_files equal to work_mem to minimize PostgreSQL logging
- Remove UseG1G.

# 2.4.1

- Do not output settings to stdout when outputting to files.
- Disable puppetdb garbage collection on compile masters.
- Add UseG1G.
- Support 2 CPU / 6 GB systems.

# 2.4.0

- Add flag to write to pe.conf.
- Discard STDERR when setting variables from command line commands.
- Tune more PostgreSQL settings.
- Avoid PuppetDB queries on older versions of PE.

# 2.3.0

- Implement compare option.

# 2.2.1

- Output details for duplicates.

# 2.2.0

- Add use_current_memory_per_jruby option.
- Buffer collection of current settings.

# 2.1.0

- Rename face.

# 2.0.2

- Update face documentation.

# 2.0.1

- Rename task.
- Note that the name of this module (and its face and task) are in flux.

# 2.0.0

- Implement as a module with a face and a task.

# 1.7.0

- Refactor use of PuppetDB

# 1.6.1

- Move cli code to separate file.
- Rename configuration class to query.
- Handle exceptions when PuppetDB is unavailable.
- Add spec tests.

# 1.6.0

- Improve estimate output and translation test.

# 1.5.0

- Implement extra large reference architecture.

# 1.3.0

- Add translation method
- Limit command_processing_threads
- Move inventory into its own class

# 1.2.3

- Refactor calculate methods.

## 1.2.1

- Remove dependency on pe.conf.
- Refactor roles, profiles, and components mappings.

## 1.2.0

- Allow use of the local system or an inventory file instead of PuppetDB.

## 1.1.1

- Update to PDK 1.7.0
