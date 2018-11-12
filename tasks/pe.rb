#!/opt/puppetlabs/puppet/bin/ruby

require 'facter'
require 'json'
require 'open3'
require 'puppet'
require 'timeout'

Puppet.initialize_settings

# Read parameters, set defaults, and validate values.

def read_parameters
  input = read_stdin
  output = {}

  # Validate parameter values or return errors.

  unless safe_hiera_path?(input['hiera'])
    return_error _("The 'hiera' parameter must be a subdirectory in %{paths}") % { paths: safe_hiera_paths.join(' or ') }
  end

  return_error("The 'memory_per_jruby' parameter must be an integer")       unless safe_memory?(input['memory_per_jruby'])
  return_error("The 'memory_reserved_for_os' parameter must be an integer") unless safe_memory?(input['memory_reserved_for_os'])

  output['common']                 = optional_true(input['common'])    ? '--common' : ''
  output['hiera']                  = (input['hiera'])                  ? "--hiera=#{input['hiera']}"                                        : ''
  output['memory_per_jruby']       = (input['memory_per_jruby'])       ? "--memory_per_jruby=#{input['memory_per_jruby'].to_i}"             : ''
  output['memory_reserved_for_os'] = (input['memory_reserved_for_os']) ? "--memory_reserved_for_os=#{input['memory_reserved_for_os'].to_i}" : ''

  output
end

# Read parameters as JSON from STDIN.

def read_stdin
  input = {}
  begin
    Timeout.timeout(3) do
      input = JSON.parse(STDIN.read)
    end
  rescue Timeout::Error
    return_error('Cannot read parameters as JSON from STDIN')
  end
  input
end

# Handle "Optional[Variant[Boolean,Enum['true','false']]]"

def optional_true(param)
  return false unless param
  return true if param == true
  param == 'true'
end

# Validation

def safe_hiera_paths
  ['/tmp/', "#{Puppet[:environmentpath]}/#{Puppet[:environment]}/"]
end

def safe_hiera_path?(param)
  return true unless param
  path = File.absolute_path(param)
  safe_hiera_paths.each do |safe_hiera_path|
    return true if path.start_with?(safe_hiera_path)
  end
  false
end

def safe_memory?(param)
  return true unless param
  (param =~ %r{^\d+$}) != nil
end

# Execute a command with an array of arguments and return the result as a hash.

def execute_command(command, args = [])
  # '/opt/puppetlabs/bin' is not in PATH, but is require to execute 'puppet infra' commands.
  command_env = { 'PATH' => "#{ENV['PATH']}:/opt/puppetlabs/bin" }
  # Convert each element of the args array to a string.
  args = args.reject { |a| a.empty? }.map(&:to_s)
  # Execute the command with the arguments passed as a variable length argument list using the asterisk operator.
  stdout, stderr, status = Open3.capture3(command_env, command, *args)
  # Merge the command and args into a string.
  command_line = args.unshift(command).join(' ')
  { command: command_line, status: status.exitstatus, stdout: stdout.strip, stderr: stderr.strip }
end

# Return an error and exit.

def return_error(message)
  result = {}
  result[:_error] = {
    msg:     message,
    kind:    'pe_tune/failure',
    details: {}
  }
  puts result.to_json
  exit 1
end

# Return the error results of a command and exit.

def return_command_error(params, command_results)
  result = {}
  result[:status]  = 'failure'
  result[:command] = command_results[:command]
  result[:error]   = command_results[:stderr]
  result[:results] = command_results[:stdout]
  result[:params]  = params
  puts result.to_json
  exit 1
end

# Return the results of a command and exit.

def return_command_results(_params, command_results)
  result = {}
  result[:status]  = 'success'
  result[:command] = command_results[:command]
  result[:results] = command_results[:stdout]
  puts result.to_json
  exit 0
end

######
# Main
######

# Master validation.

unless File.exist?('/opt/puppetlabs/bin/puppetserver')
  return_error('This node does not appear to be the primary master')
end

params = read_parameters

command = 'puppet'
options = ['tune', 'pe',
  params['common'],
  params['hiera'],
  params['memory_per_jruby'],
  params['memory_reserved_for_os'],
]

results = execute_command(command, options)

if results[:status] != 0
  return_command_error(params, results)
else
  return_command_results(params, results)
end
