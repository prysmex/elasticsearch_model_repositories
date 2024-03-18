# frozen_string_literal: true

require_relative 'elasticsearch_repositories/version'

# elasticsearch
require 'elasticsearch'

# activesupport
require 'active_support/callbacks'
require 'active_support/core_ext/module/delegation'

# adapter
require_relative 'elasticsearch_repositories/adapter'
require_relative 'elasticsearch_repositories/adapters/active_record'
require_relative 'elasticsearch_repositories/adapters/multistrategy'

require_relative 'elasticsearch_repositories/model'
require_relative 'elasticsearch_repositories/registry'
require_relative 'elasticsearch_repositories/search_request'

# strategy
require_relative 'elasticsearch_repositories/strategy/configuration/mappings'
require_relative 'elasticsearch_repositories/strategy/configuration/settings'
require_relative 'elasticsearch_repositories/strategy/configuration'
require_relative 'elasticsearch_repositories/strategy/importing'
require_relative 'elasticsearch_repositories/strategy/indexing'
require_relative 'elasticsearch_repositories/strategy/management'
require_relative 'elasticsearch_repositories/strategy/searching'
require_relative 'elasticsearch_repositories/strategy/serializing'
require_relative 'elasticsearch_repositories/base_strategy'
require_relative 'elasticsearch_repositories/multistrategy'

# response
require_relative 'elasticsearch_repositories/response/result'
require_relative 'elasticsearch_repositories/response/records'
require_relative 'elasticsearch_repositories/response/aggregations'
require_relative 'elasticsearch_repositories/response/suggestions'
require_relative 'elasticsearch_repositories/response'

#
# Base module that allows gem configuration, and be used to store a cache of an Elasticsearch::Client
# It also provides a *search* method for executing multistrategy searches
#
module ElasticsearchRepositories

  class << self

    # Creates and caches an Elasticsearch::Client
    #
    # @return [Elasticsearch::Client]
    def client
      @client ||= Elasticsearch::Client.new
    end

    # Overrides cached elasticsearch client
    #
    # @param [Elasticsearch::Client] client
    # @return [Elasticsearch::Client]
    def client=(client)
      @client = client
    end

    # Search across multiple strategies
    #
    # @query_or_payload [String,Hash]
    # @strategies [Array] array of strategies (ElasticsearchRepositories::BaseStrategy)
    # @options [Hash] options to pass to the search request ToDo (detail)
    def search(query_or_payload, strategies = [], options = {})
      wrapper = ElasticsearchRepositories::Multistrategy::MultistrategyWrapper.new(strategies)
      search = ElasticsearchRepositories::SearchRequest.new(wrapper, query_or_payload, options)
      ElasticsearchRepositories::Response::Response.new(wrapper, search, options)
    end

    # @todo
    #
    # def scroll
    # end

    # @todo
    #
    # def search_and_scroll
    # end

    # Yield self to allow configuing in a block
    def configure
      yield self
    end

    # Temporarily sets a value for 'refresh_interval' setting
    #
    # @param [BaseStrategy] strategy
    # @param [String] index
    # @param [String] interval
    # @return [void]
    def with_refresh_interval(strategy, index, interval)
      return yield if interval == false

      current_interval = strategy
        .client
        .indices
        .get_settings(index:)
        .dig(index, 'settings', 'index', 'refresh_interval') || '1s'

      strategy.client.indices.put_settings(
        body: { index: { refresh_interval: interval } },
        index:
      )

      yield
    ensure
      # restore refresh_interval
      strategy.client.indices.put_settings(
        body: { index: { refresh_interval: current_interval } },
        index:
      )
    end

    # @example
    #
    #   with_timer do |ruler|
    #     ruler.call(:foo) do
    #       sleep(1)
    #     end

    #     ruler.call(:foo) do
    #       sleep(2)
    #     end
    #   end
    #
    #   => {:foo=>[1.001047, 2.001069]}
    #
    # @param [Boolean] average
    # @return [Hash{* => Array<Integer>}]
    def with_timer(average: false)
      obj = {}
      wrapper = ->(key, normalizer = nil, &block) do
        key_array = obj[key] ||= []

        now = Time.now
        value = block.call
        took = Time.now - now
        took = normalizer.call(took) if normalizer
        key_array.push(took)
        [value, took]
      end
      yield wrapper, obj
      obj = obj.transform_values! { |v| v.sum(0.0) / v.size } if average
      obj
    end

  end

end
