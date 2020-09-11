require 'hashie/mash'

require 'elasticsearch'

require_relative 'elasticsearch_model_repositories/version'

# require_relative 'elasticsearch_model_repositories/client'
require_relative 'elasticsearch_model_repositories/hash_wrapper'
require_relative 'elasticsearch_model_repositories/importing'
require_relative 'elasticsearch_model_repositories/model'

require_relative 'elasticsearch_model_repositories/strategy/configuration'
require_relative 'elasticsearch_model_repositories/strategy/importing'
require_relative 'elasticsearch_model_repositories/strategy/indexing'
require_relative 'elasticsearch_model_repositories/strategy/management'
require_relative 'elasticsearch_model_repositories/strategy/searching'
require_relative 'elasticsearch_model_repositories/strategy/serializing'
require_relative 'elasticsearch_model_repositories/base_strategy'

require_relative 'elasticsearch_model_repositories/response/base'
require_relative 'elasticsearch_model_repositories/response/result'
require_relative 'elasticsearch_model_repositories/response/results'
require_relative 'elasticsearch_model_repositories/response/records'
require_relative 'elasticsearch_model_repositories/response/aggregations'
require_relative 'elasticsearch_model_repositories/response/suggestions'
require_relative 'elasticsearch_model_repositories/response'

require_relative 'elasticsearch_model_repositories/adapter'
require_relative 'elasticsearch_model_repositories/adapters/active_record'
require_relative 'elasticsearch_model_repositories/adapters/default'
require_relative 'elasticsearch_model_repositories/adapters/mongoid'

module ElasticsearchModelRepositories
  module ClassMethods

    def client
      @client ||= Elasticsearch::Client.new
    end

    def client=(client)
      @client = client
    end

  end

  extend ClassMethods
end
