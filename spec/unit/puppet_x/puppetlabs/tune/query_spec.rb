require 'spec_helper'

require 'puppet_x/puppetlabs/tune/query.rb'

def suppress_standard_output
  allow(STDOUT).to receive(:puts)
end

describe PuppetX::Puppetlabs::Tune::Query do
  subject(:query) { described_class.new }

  let(:pql_data) do
    [
      { "metrics" =>
        { "data" =>
          [
            { "name" => "foo", "value" => 75.181073364999975, "category" => "time" },
            { "name" => "bar", "value" => 28.589005453, "category" => "time" },
            { "name" => "config_retrieval", "value" => 50.181073364999975, "category" => "time" },
          ] } },
      { "metrics" =>
        { "data" =>
          [
            { "name" => "foo", "value" => 8.181073364999975, "category" => "time" },
            { "name" => "bar", "value" => 28.589005453, "category" => "time" },
            { "name" => "config_retrieval", "value" => 50.181073364999975, "category" => "time" },
          ] } }
    ]
  end

  describe '#average_metric_time' do
    context 'when data contains time values for the given metric' do
      it 'returns the average of the metric\'s data' do
        expect(query.average_metric_time(pql_data, 'foo', 'bar')).to eq(42)
      end
    end

    context 'when data does not contain time values for the given metric' do
      it 'returns nil' do
        expect(query.average_metric_time([{}], 'foo', 'bar')).to eq(nil)
      end
    end
  end

  # describe '#average_compile_time_for_range' do
  #   context 'when data contains values in the given time range' do
  #     it 'returns the average of the config_retrieval data' do
  #       pending("Cannot test without puppetdb installed")
  #       expect(query.average_compile_time_for_range('2019-01-01', '2019-12-31')).to eq(50)
  #     end
  #   end
  # end
end
