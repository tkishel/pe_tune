require 'spec_helper_acceptance'

# BEAKER_provision=yes PUPPET_INSTALL_TYPE=pe bundle exec rake beaker:default

describe 'run' do
  context 'puppet pe tune' do
    it 'and output optimized settings' do
      on(master, puppet('pe', 'tune'), acceptable_exit_codes: 0) do |result|
        expect(result.stdout).to match(%r{CPU Summary})
      end
    end

    it 'and output current settings' do
      on(master, puppet('pe', 'tune', '--current'), acceptable_exit_codes: 0) do |result|
        expect(result.stdout).to match(%r{Found (defined|default) settings})
      end
    end

    it 'and compare current and optimized settings' do
      on(master, puppet('pe', 'tune', '--compare'), acceptable_exit_codes: 0) do |result|
        expect(result.stdout).to match(%r{No defined settings to compare}) # or %r{Defined and optimized settings (match|vary)}
      end
    end

    it 'and output current settings to pe_conf' do
      on(master, puppet('pe', 'tune', '--local', '--pe_conf'), acceptable_exit_codes: 0) do |result|
        expect(result.stdout).to match(%r{Merged optimized settings})
      end
    end

    it 'and output current settings to hiera' do
      on(master, puppet('pe', 'tune', '--hiera', '/tmp/xyz'), acceptable_exit_codes: 0) do |result|
        expect(result.stdout).to match(%r{Wrote Hiera YAML file})
      end
    end
  end
end
