require 'puppetlabs_spec_helper/rake_tasks'
require 'rspec/core/rake_task'

desc 'run static analysis with rubocop'
task(:rubocop) do
  require 'rubocop'
  cli = RuboCop::CLI.new
  exit cli.run(%w[-D -f s])
end

namespace(:spec) do
  desc 'run rspec unit tests'
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.pattern = 'spec/unit/**{,/*/**}/*_spec.rb'
  end
end
