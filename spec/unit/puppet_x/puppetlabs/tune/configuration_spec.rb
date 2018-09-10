require 'spec_helper'

# require 'puppet_x/puppetlabs/tune/configuration.rb'
#
# describe PuppetX::Puppetlabs::Tune::Configuration do
#   subject(:configurator) { described_class.new }
#   context 'when pe.conf does not exist' do
#     it 'when pe.conf does not exist' do
#       configurator.instance_variable_set(:@pe_conf, {})
#       expect((configurator.send :find_pe_conf_host, 'puppet_master_host')).to eq(nil)
#     end
#   end
#   context 'when pe.conf exists' do
#     it 'does not contain puppet_master_host' do
#       configurator.instance_variable_set(:@pe_conf, { 'puppet_enterprise::console_host' => 'console.example.com' })
#       expect((configurator.send :identify_pe_conf_database_host, 'puppet_master_host')).to eq(nil)
#     end
#     it 'contains puppet_master_host' do
#       configurator.instance_variable_set(:@pe_conf, { 'puppet_enterprise::puppet_master_host' => 'master.example.com' })
#       expect((configurator.send :identify_pe_conf_database_host, 'puppet_master_host')).to eq('master.example.com')
#     end
#  end
# end
