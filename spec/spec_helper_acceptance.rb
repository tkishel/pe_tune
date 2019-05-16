require 'beaker-pe'
require 'beaker-puppet'
require 'beaker-rspec/helpers/serverspec'
require 'beaker-rspec/spec_helper'
require 'beaker-task_helper'
require 'beaker/module_install_helper'
require 'beaker/puppet_install_helper'

if ENV['BEAKER_provision'] != 'no'
  run_puppet_install_helper
  install_module_on(hosts)
end

RSpec.configure do |c|
  c.before :suite do
    unless ENV['BEAKER_TESTMODE'] == 'local'
      unless ENV['BEAKER_provision'] == 'no'
        # intentionally blank
      end
      hosts.each do |host|
        # intentionally blank
      end
    end
  end
end
