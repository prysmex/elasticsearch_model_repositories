require 'test_helper'

class ElasticsearchModelRepositoriesTest < Minitest::Test

  def setup
    @klass = ElasticsearchRepositories
  end
  
  def test_client
    client = @klass.client
    assert_instance_of Elasticsearch::Client, client
    assert_same client, @klass.client
  end

  def test_client=
    @klass.client = 1
    assert_equal @klass.client, 1
    @klass.client = nil
  end

  def test_search
    query = {query: {match_all: {}}}
    strategy_mock = Minitest::Mock.new
    def strategy_mock.search_index_name; 'test_index'; end

    response = @klass.search(query, [strategy_mock, strategy_mock])
    assert_instance_of ElasticsearchRepositories::Response::Response, response
    assert_instance_of ElasticsearchRepositories::Multistrategy::MultistrategyWrapper, response.strategy_or_wrapper
    assert_equal response.search.definition[:body], query
    assert_equal response.search.definition[:index], ['test_index', 'test_index']
  end

  def test_configure
    ElasticsearchRepositories.configure do |value|
      assert_equal value, ElasticsearchRepositories
    end
  end

end