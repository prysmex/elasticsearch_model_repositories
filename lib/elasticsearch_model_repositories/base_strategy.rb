# require_relative 'strategy/configuration'
# require_relative 'strategy/importing'
# require_relative 'strategy/indexing'
# require_relative 'strategy/management'
# require_relative 'strategy/searching'
# require_relative 'strategy/serializing'

module ElasticsearchModelRepositories
  class BaseStrategy

    include ElasticsearchModelRepositories::Strategy::Configuration::Methods
    include ElasticsearchModelRepositories::Strategy::Importing
    include ElasticsearchModelRepositories::Strategy::Indexing
    include ElasticsearchModelRepositories::Strategy::Management
    include ElasticsearchModelRepositories::Strategy::Searching::Methods
    include ElasticsearchModelRepositories::Strategy::Serializing

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