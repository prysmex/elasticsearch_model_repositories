require 'test_helper'

class SearchRequestTest < Minitest::Test
  extend Minitest::Spec::DSL

  def test_supports_callbacks
    modules = ElasticsearchRepositories::SearchRequest.included_modules
    assert modules.include?(ActiveSupport::Callbacks)
  end

  def test_has_execute_callback
    callbacks = ElasticsearchRepositories::SearchRequest.__callbacks
    assert callbacks.key?(:execute)
  end

  let(:strategy_mock) do
    mock = Minitest::Mock.new
    def mock.search_index_name; 'test_index'; end
    mock
  end

  describe "#initialize" do

    it "adds body to definition" do
      search_request = ElasticsearchRepositories::SearchRequest.new(
        strategy_mock,
        {}
      )
      assert_equal search_request.definition[:index], 'test_index'
    end

    describe "when query is a hash or stringified hash" do
      let(:queries) {
        [
          {query: {match_all: {}}},
          "{\"query\":{\"match_all\":{}}}"
        ]
      }
  
      it "adds body to definition" do
        queries.each do |query|
          search_request = ElasticsearchRepositories::SearchRequest.new(
            strategy_mock,
            query
          )
          assert_nil search_request.definition[:q]
          assert_equal search_request.definition[:body], query
        end
      end

    end

    describe "when query is a string" do
      let(:queries) {
        ["some string"]
      }
  
      it "adds body to definition" do
        queries.each do |query|
          search_request = ElasticsearchRepositories::SearchRequest.new(
            strategy_mock,
            query
          )
          assert_nil search_request.definition[:body]
          assert_equal search_request.definition[:q], query
        end
      end

    end


  end

  # describe "#execute!" do
  #   it 'calls client.search, passing @definition' do
  #   end

  #   it 'returns client.search return value when has callbacks' do
  #   end

  #   it 'returns client.search return value when no callbacks' do
  #   end
  # end

end