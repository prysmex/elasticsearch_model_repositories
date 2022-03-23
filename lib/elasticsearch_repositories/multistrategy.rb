module ElasticsearchRepositories
  module Multistrategy

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
      # @return Elastic::Transport::Client
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