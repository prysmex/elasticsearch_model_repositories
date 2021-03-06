require 'hashie/mash'

require 'elasticsearch'

require_relative 'elasticsearch_repositories/version'

# require_relative 'elasticsearch_repositories/client'
require_relative 'elasticsearch_repositories/hash_wrapper'
require_relative 'elasticsearch_repositories/importing'
require_relative 'elasticsearch_repositories/model'
require_relative 'elasticsearch_repositories/registry'

require_relative 'elasticsearch_repositories/strategy/configuration'
require_relative 'elasticsearch_repositories/strategy/importing'
require_relative 'elasticsearch_repositories/strategy/indexing'
require_relative 'elasticsearch_repositories/strategy/management'
require_relative 'elasticsearch_repositories/strategy/searching'
require_relative 'elasticsearch_repositories/strategy/serializing'
require_relative 'elasticsearch_repositories/base_strategy'
require_relative 'elasticsearch_repositories/multistrategy'

require_relative 'elasticsearch_repositories/response/result'
# require_relative 'elasticsearch_repositories/response/results'
require_relative 'elasticsearch_repositories/response/records'
require_relative 'elasticsearch_repositories/response/aggregations'
require_relative 'elasticsearch_repositories/response/suggestions'
require_relative 'elasticsearch_repositories/response'

require_relative 'elasticsearch_repositories/adapter'
require_relative 'elasticsearch_repositories/adapters/active_record'
require_relative 'elasticsearch_repositories/adapters/default'
require_relative 'elasticsearch_repositories/adapters/multistrategy'

module ElasticsearchRepositories
  module ClassMethods

    def client
      @client ||= Elasticsearch::Client.new
    end

    def client=(client)
      @client = client
    end

    # Search across multiple strategies
    def search(query_or_payload, strategies=[], options={})
      wrapper = ElasticsearchRepositories::Multistrategy::MultistrategyWrapper.new(strategies)
      search = ElasticsearchRepositories::Strategy::Searching::SearchRequest.new(wrapper, query_or_payload, options)
      ElasticsearchRepositories::Response::Response.new(wrapper, search)
    end

  end

  extend ClassMethods
end
