module ElasticsearchRepositories
  module Multistrategy
    
    # # used to keep track which classes have the ElasticsearchRepositories::Model
    # # module included
    # class ClassRegistry
    #   def initialize
    #     @models = []
    #   end

    #   # Returns the unique instance of the registry (Singleton)
    #   #
    #   # @api private
    #   #
    #   def self.__instance
    #     @instance ||= new
    #   end

    #   # Adds a model to the registry
    #   #
    #   def self.add(klass)
    #     __instance.add(klass)
    #   end

    #   # Returns an Array of registered models
    #   #
    #   def self.all
    #     __instance.models
    #   end

    #   # Adds a model to the registry
    #   #
    #   def add(klass)
    #     @models << klass
    #   end

    #   # Returns a copy of the registered models
    #   #
    #   def models
    #     @models
    #   end
    # end

    # Wraps a collection of strategies to support multistrategy-querying
    # @see ElasticsearchRepositories.search
    class MultistrategyWrapper
      attr_reader :strategies

      # @param strategies [Strategy] The list of strategies across which the search will be performed
      def initialize(strategies)
        @strategies = strategies
      end

      def search_index_name
        strategies.map { |s| s.search_index_name }
      end

      # Get the common client for all strategies
      # @return Elasticsearch::Transport::Client
      def client
        _strategies = strategies.map { |s| s.client }.uniq
        if _strategies.size == 1
          _strategies.first
        else
          raise StandardError.new('Multistrategy defined with strategies with different elasticsearch clients')
        end
      end

      def host_class
        strategies.map { |s| s.host_class }
      end

    end

  end
end