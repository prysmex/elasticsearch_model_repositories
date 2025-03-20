# frozen_string_literal: true

require_relative 'elasticsearch_repositories/version'

# elasticsearch
require 'elasticsearch'

# activesupport
require 'active_support'
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

  @allow_ar_order = false

  class << self

    attr_accessor :allow_ar_order

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
    # def search_and_auto_search_after
    # end

    # @todo
    #
    # def search_and_auto_scroll
    # end

    # @todo
    #
    # def search_and_auto_search_after_or_auto_scroll
    # end

    # Yield self to allow configuing in a block
    def configure
      yield self
    end

    # Temporarily sets a value for 'refresh_interval' setting
    #
    # @param [BaseStrategy] strategy
    # @param [String] index
    # @param [NilClass|String|FalseClass] tmp_interval
    # @options [Hash]
    # @option current_interval [NilClass|String]
    # @return [void]
    def with_refresh_interval(strategy, index, tmp_interval, **options)
      # do nothing with refresh_interval when tmp_interval is false
      return yield if tmp_interval == false

      # allow setting nil without trying to default
      current_interval = if options.key?(:refresh_interval)
        options[:refresh_interval]
      else
        # default from current
        begin
          strategy
            .client
            .indices
            .get_settings(index:)
            .dig(index, 'settings', 'index', 'refresh_interval')
        rescue Elastic::Transport::Transport::Errors::NotFound => _e
          strategy.settings.to_hash.dig(:index, :refresh_interval)
        end
      end

      strategy.client.indices.put_settings(
        body: { index: { refresh_interval: tmp_interval } },
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
    def with_timer(average: false, processor: nil)
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
      return obj unless average || processor

      obj.transform_values do |v|
        v = (v.sum(0.0) / v.size).round(2) if average
        v = processor.call(v) if processor
        v
      end
    end

  end

end
