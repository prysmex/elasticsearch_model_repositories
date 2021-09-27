require_relative 'elasticsearch_repositories/version'

# elasticsearch
require 'elasticsearch'

# activesupport
require 'active_support/core_ext/module/delegation'

# adapter
require_relative 'elasticsearch_repositories/adapter'
require_relative 'elasticsearch_repositories/adapters/active_record'
require_relative 'elasticsearch_repositories/adapters/multistrategy'

require_relative 'elasticsearch_repositories/model'
require_relative 'elasticsearch_repositories/registry'
require_relative 'elasticsearch_repositories/search_request'

# strategy
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
    # @return [Elasticsearch::Client]
    def client
      @client ||= Elasticsearch::Client.new
    end
  
    # Overrides cached elasticsearch client
    # @param [Elasticsearch::Client] client
    # @return [Elasticsearch::Client]
    def client=(client)
      @client = client
    end
  
    # Search across multiple strategies
    # @query_or_payload [String,Hash]
    # @strategies [Array] array of strategies (ElasticsearchRepositories::BaseStrategy)
    # @options [Hash] options to pass to the search request ToDo (detail)
    def search(query_or_payload, strategies=[], options={})
      wrapper = ElasticsearchRepositories::Multistrategy::MultistrategyWrapper.new(strategies)
      search = ElasticsearchRepositories::SearchRequest.new(wrapper, query_or_payload, options)
      ElasticsearchRepositories::Response::Response.new(wrapper, search, options)
    end
  
    # Yield self to allow configuing in a block
    def configure
      yield self
    end

  end

end
