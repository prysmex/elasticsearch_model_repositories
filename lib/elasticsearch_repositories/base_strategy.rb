# require_relative 'strategy/configuration'
# require_relative 'strategy/importing'
# require_relative 'strategy/indexing'
# require_relative 'strategy/management'
# require_relative 'strategy/searching'
# require_relative 'strategy/serializing'

module ElasticsearchRepositories
  
  #
  # Use this class as a base to create your own strategies by inheriting from it.
  # Once you've defined this defined your strategy, you can register it in your models
  # by calling ElasticsearchRepositories::Model::ClassMethods#register_stratgy
  #
  # @abstract
  #
  class BaseStrategy

    include ElasticsearchRepositories::Strategy::Configuration::Methods
    include ElasticsearchRepositories::Strategy::Importing
    include ElasticsearchRepositories::Strategy::Indexing
    include ElasticsearchRepositories::Strategy::Management
    include ElasticsearchRepositories::Strategy::Searching
    include ElasticsearchRepositories::Strategy::Serializing

    attr_reader :host_class
    attr_reader :client
    attr_reader :name

    # @param [YourModel] host_class Class that uses the strategy
    # @param [Elastic::Transport::Client] client elasticsearch client
    # @param [String] name the identifier of the strategy
    # @param [Proc] &block used to configure the strategy
    #
    def initialize(host_class, client, name=nil, &block)
      @host_class = host_class
      @client = client
      @name = name
      self.instance_eval(&block) if block_given?
    end
    
    # excecutes the block on the strategy's context. Useful to override/update methods
    # @return [void]
    def update(&block)
      self.instance_eval(&block) if block_given?
    end

  end
end