# require_relative 'strategy/configuration'
# require_relative 'strategy/importing'
# require_relative 'strategy/indexing'
# require_relative 'strategy/management'
# require_relative 'strategy/searching'
# require_relative 'strategy/serializing'

module ElasticsearchRepositories
  class BaseStrategy

    include ElasticsearchRepositories::Strategy::Configuration::Methods
    include ElasticsearchRepositories::Strategy::Importing
    include ElasticsearchRepositories::Strategy::Indexing
    include ElasticsearchRepositories::Strategy::Management
    include ElasticsearchRepositories::Strategy::Searching::Methods
    include ElasticsearchRepositories::Strategy::Serializing

    attr_reader :client
    attr_reader :host
    attr_reader :name
      
    def initialize(klass, client, name=nil, &block)
      @host = klass
      @client = client
      @name = name
      self.instance_eval(&block) if block_given?
    end
    
    #update the strategy's methods
    def update(&block)
      self.instance_eval(&block) if block_given?
    end

  end
end