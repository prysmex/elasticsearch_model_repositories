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
  # @warning
  #
  #   This class instances are designed to be 'registered' to a model
  #   which can lead to issues regarding threat safety. Please refrain from
  #   adding state to the instance
  #
  class BaseStrategy

    include ElasticsearchRepositories::Strategy::Configuration
    include ElasticsearchRepositories::Strategy::Importing
    include ElasticsearchRepositories::Strategy::Indexing
    include ElasticsearchRepositories::Strategy::Management
    include ElasticsearchRepositories::Strategy::Searching
    include ElasticsearchRepositories::Strategy::Serializing

    attr_reader :host_class
    attr_reader :client
    attr_reader :name

    CONFIGURABLE_METHODS = %i(
      target_index_name search_index_name current_index_name
      reindexing_index_iterator index_without_id as_indexed_json
      index_record_to_es reindexing_includes_proc
    ).freeze

    class << self

      # Synthatic sugar for overriding methods when subclassing.
      # The advantage is that it gives a 'clearer' visual aid
      # to someone reading code that some known method is being overriden.
      #
      # It also validates that methods are indeed known
      #
      # @example
      #
      # class Simple < ElasticsearchRepositories::BaseStrategy
      #   configure {
      #     search_index_name: ->(record) {
      #       host_class._base_index_name
      #     },
      #     target_index_name: ->(record) {
      #       search_index_name
      #     }
      #   }
      # end
      #
      # instead of
      #
      # class Simple < ElasticsearchRepositories::BaseStrategy
      #   def search_index_name(record)
      #     host_class._base_index_name
      #   end
      #
      #   def target_index_name(record)
      #     search_index_name
      #   end
      # end
      #
      # @param [Hash{Symbol => lambda}]
      # @return [void]
      def configure(hash)
        hash.each do |name, proc|
          unless CONFIGURABLE_METHODS.include?(name.to_sym)
            msg = "configure only accepts known methods: #{CONFIGURABLE_METHODS.join(', ')}. Got: #{name}"
            raise NoMethodError.new(msg)
          end
          define_method(name, &proc)
        end
      end

    end

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

    # Same as class method 'configure' but for an instance
    #
    # @param [Hash{Symbol => lambda}]
    # @return [void]
    def configure_instance(hash)
      hash.each do |name, proc|
        unless CONFIGURABLE_METHODS.include?(name.to_sym)
          msg = "configure only accepts known methods: #{CONFIGURABLE_METHODS.join(', ')}. Got: #{name}"
          raise NoMethodError.new(msg)
        end
        define_singleton_method(name, &proc)
      end
    end

  end
end